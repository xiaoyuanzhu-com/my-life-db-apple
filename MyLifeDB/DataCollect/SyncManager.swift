//
//  SyncManager.swift
//  MyLifeDB
//
//  Orchestrates data collection from all registered collectors.
//  Triggers sync on foreground / background, handles throttling,
//  uploads to backend, and manages per-collector state.
//

import Foundation
#if os(iOS)
import BackgroundTasks
#endif

@Observable
final class SyncManager {

    // MARK: - Singleton

    static let shared = SyncManager()

    // MARK: - Observable State

    /// Overall sync state
    private(set) var state: SyncState = .idle

    /// Per-collector status (keyed by collector ID)
    private(set) var collectorStates: [String: CollectorSyncState] = [:]

    /// Last successful sync completion time
    private(set) var lastSyncDate: Date?

    /// Last sync error (nil if last sync succeeded)
    private(set) var lastError: SyncError?

    /// Result of the last sync cycle (nil if never synced)
    private(set) var lastSyncResult: SyncResult?

    /// Detailed breakdown of the last sync cycle
    private(set) var lastSyncDetail: SyncDetail?

    /// Per-day progress for full sync (nil when not doing full sync)
    var fullSyncProgress: FullSyncProgress?

    /// Whether a full sync has prior progress that can be resumed
    var hasResumableFullSync: Bool {
        let keys = UserDefaults.standard.stringArray(forKey: Self.completedMonthsKey) ?? []
        return !keys.isEmpty
    }

    // MARK: - Configuration

    /// Minimum interval between syncs (seconds)
    private let throttleInterval: TimeInterval = 300  // 5 minutes

    /// UserDefaults key for persisted full sync progress
    private static let completedMonthsKey = "sync.fullSync.completedMonths"

    // MARK: - Private

    @ObservationIgnored
    private var collectors: [DataCollector] = []

    @ObservationIgnored
    private var syncTask: Task<Void, Never>?

    @ObservationIgnored
    private let watermark = SyncWatermark()

    // MARK: - Background Task ID

    #if os(iOS)
    static let backgroundTaskID = "com.mylifedb.sync"
    #endif

    // MARK: - Init

    private init() {
        // Register all collectors
        collectors = [
            HealthKitCollector(),
            // Future: LocationCollector(),
            // Future: ScreenTimeCollector(),
        ]

        // Initialize per-collector states
        for collector in collectors {
            collectorStates[collector.id] = .idle
        }

        // Load last sync date
        lastSyncDate = UserDefaults.standard.object(forKey: "sync.lastSyncDate") as? Date
    }

    // MARK: - Public API

    /// Trigger a sync cycle. Called from scene phase handler or background task.
    /// Respects throttle interval unless `force` is true.
    @MainActor
    func sync(force: Bool = false) {
        // Don't sync if already syncing
        guard state == .idle else { return }

        // Throttle: skip if last sync was recent
        if !force, let last = lastSyncDate,
           Date().timeIntervalSince(last) < throttleInterval {
            return
        }

        // Must be authenticated
        guard AuthManager.shared.isAuthenticated else { return }

        syncTask?.cancel()
        syncTask = Task {
            await performSync()
        }
    }

    /// Trigger a full sync of all HealthKit history, month by month.
    @MainActor
    func syncAll() {
        guard state == .idle else { return }
        guard AuthManager.shared.isAuthenticated else { return }

        syncTask?.cancel()
        syncTask = Task {
            await performFullSync()
        }
    }

    /// Cancel any in-progress sync
    @MainActor
    func cancelSync() {
        syncTask?.cancel()
        syncTask = nil
        state = .idle
    }

    // MARK: - Background Task Registration

    #if os(iOS)
    /// Register the background task with the system. Call once at app launch.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskID,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            self?.handleBackgroundTask(bgTask)
        }
    }

    /// Schedule the next background sync.
    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)  // ~4 hours
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        // Schedule the next one
        scheduleBackgroundSync()

        let syncTask = Task {
            await performSync()
        }

        // If system kills the task, cancel our sync
        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            _ = await syncTask.value
            task.setTaskCompleted(success: lastError == nil)
        }
    }
    #endif

    // MARK: - Core Sync Logic

    @MainActor
    private func performSync(fullSync: Bool = false) async {
        state = fullSync ? .syncingAll : .syncing
        lastError = nil

        var uploadedCount = 0
        var skippedCount = 0
        var failures: [String: String] = [:]
        var collectorsRun = 0
        var totalSamplesCollected = 0
        var totalTypesQueried = 0
        var totalTypesWithData = 0
        var authorizationRequested = false

        for collector in collectors {
            // Skip collectors with no enabled sources
            guard collector.hasEnabledSources else { continue }

            collectorsRun += 1

            // Check for cancellation
            guard !Task.isCancelled else {
                state = .idle
                return
            }

            // Request authorization if needed
            let authStatus = collector.authorizationStatus()
            if authStatus == .notDetermined {
                authorizationRequested = true
                let granted = await collector.requestAuthorization()
                if !granted {
                    failures[collector.id] = "Permission denied"
                    collectorStates[collector.id] = .error("Permission denied")
                    continue
                }
            } else if authStatus == .denied || authStatus == .restricted {
                failures[collector.id] = "Permission denied"
                collectorStates[collector.id] = .error("Permission denied")
                continue
            } else if authStatus == .unavailable {
                // Silently skip unavailable collectors
                collectorsRun -= 1
                continue
            }

            collectorStates[collector.id] = .collecting

            do {
                // 1. Collect new samples (now returns CollectionResult with stats)
                let result = try await collector.collectNewSamples(fullSync: fullSync)
                let batches = result.batches

                // Accumulate stats
                totalSamplesCollected += result.stats.samplesCollected
                totalTypesQueried += result.stats.typesQueried
                totalTypesWithData += result.stats.typesWithData

                guard !batches.isEmpty else {
                    collectorStates[collector.id] = .idle
                    continue
                }

                collectorStates[collector.id] = .uploading(progress: 0)
                var collectorFailures = 0

                // 2. Upload each day's batch
                for (index, batch) in batches.enumerated() {
                    guard !Task.isCancelled else {
                        state = .idle
                        return
                    }

                    // Watermark check: skip if file hasn't changed
                    if !watermark.hasChanged(path: batch.uploadPath, data: batch.data) {
                        skippedCount += 1
                        let progress = Double(index + 1) / Double(batches.count)
                        collectorStates[collector.id] = .uploading(progress: progress)
                        continue
                    }

                    do {
                        try await APIClient.shared.saveRawFile(
                            path: batch.uploadPath,
                            data: batch.data
                        )

                        // Record watermark AFTER successful upload
                        watermark.recordUpload(path: batch.uploadPath, data: batch.data)

                        // Commit anchor ONLY after successful upload
                        await collector.commitAnchor(for: batch)
                        uploadedCount += 1

                        let progress = Double(index + 1) / Double(batches.count)
                        collectorStates[collector.id] = .uploading(progress: progress)

                    } catch {
                        // Partial failure: anchor NOT committed, will retry next sync
                        collectorFailures += 1
                        failures["\(collector.id)/\(batch.uploadPath)"] = error.localizedDescription
                    }
                }

                // Set collector state based on whether any batch failed
                if collectorFailures > 0 {
                    collectorStates[collector.id] = .error("\(collectorFailures) upload\(collectorFailures == 1 ? "" : "s") failed")
                } else {
                    collectorStates[collector.id] = .idle
                }

            } catch {
                // Collector-level failure
                failures[collector.id] = error.localizedDescription
                collectorStates[collector.id] = .error(error.localizedDescription)
            }
        }

        // Update final state
        if !failures.isEmpty {
            lastError = SyncError(failures: failures)
        }

        // Always update sync date — the sync ran
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "sync.lastSyncDate")

        // Build detailed sync breakdown
        let errorCount = failures.count
        lastSyncDetail = SyncDetail(
            samplesCollected: totalSamplesCollected,
            typesQueried: totalTypesQueried,
            typesWithData: totalTypesWithData,
            filesUploaded: uploadedCount,
            filesSkipped: skippedCount,
            filesFailed: errorCount,
            collectorsRun: collectorsRun,
            authorizationRequested: authorizationRequested
        )

        // Determine sync result
        if uploadedCount > 0 && errorCount == 0 {
            lastSyncResult = .success(fileCount: uploadedCount)
        } else if uploadedCount > 0 && errorCount > 0 {
            lastSyncResult = .partial(uploaded: uploadedCount, failed: errorCount)
        } else if errorCount > 0 {
            lastSyncResult = .failed(errors: errorCount)
        } else {
            lastSyncResult = .noNewData
        }

        state = .idle
    }

    // MARK: - Full Sync (Month-by-Month)

    /// Discovers the HealthKit date range and builds the calendar model for full sync.
    @MainActor
    func prepareFullSync() async {
        guard let hkCollector = collectors.first(where: { $0 is HealthKitCollector }) as? HealthKitCollector else {
            return
        }

        guard let range = await hkCollector.discoverDateRange() else { return }

        let calendar = Calendar(identifier: .gregorian)
        let startComponents = calendar.dateComponents([.year, .month], from: range.start)
        let endComponents = calendar.dateComponents([.year, .month], from: range.end)

        guard let startYear = startComponents.year, let startMonth = startComponents.month,
              let endYear = endComponents.year, let endMonth = endComponents.month else {
            return
        }

        var progress = FullSyncProgress(
            startYear: startYear, startMonth: startMonth,
            endYear: endYear, endMonth: endMonth
        )

        // Restore completed months from UserDefaults
        let completedKeys = Set(
            UserDefaults.standard.stringArray(forKey: Self.completedMonthsKey) ?? []
        )
        if !completedKeys.isEmpty {
            progress.restoreCompleted(completedKeys)
        }

        fullSyncProgress = progress
    }

    /// Core month-by-month full sync orchestration.
    /// Iterates oldest-first through every month in the HealthKit date range,
    /// collecting samples and workouts for each month, then uploading day-by-day.
    @MainActor
    private func performFullSync() async {
        guard let hkCollector = collectors.first(where: { $0 is HealthKitCollector }) as? HealthKitCollector else {
            state = .idle
            return
        }

        state = .syncingAll
        lastError = nil

        // Authorization check (same pattern as performSync)
        let authStatus = hkCollector.authorizationStatus()
        if authStatus == .notDetermined {
            let granted = await hkCollector.requestAuthorization()
            if !granted {
                lastError = SyncError(failures: [hkCollector.id: "Permission denied"])
                state = .idle
                return
            }
        } else if authStatus == .denied || authStatus == .restricted {
            lastError = SyncError(failures: [hkCollector.id: "Permission denied"])
            state = .idle
            return
        } else if authStatus == .unavailable {
            state = .idle
            return
        }

        // Build calendar model if not already built
        if fullSyncProgress == nil {
            await prepareFullSync()
        }
        guard fullSyncProgress != nil else {
            // No data range found
            lastSyncResult = .noNewData
            state = .idle
            return
        }

        var totalUploaded = 0
        var totalSkipped = 0
        var failures: [String: String] = [:]

        // Loop through months oldest first
        for monthIndex in fullSyncProgress!.months.indices {
            guard !Task.isCancelled else {
                state = .idle
                return
            }

            let monthProgress = fullSyncProgress!.months[monthIndex]

            // Skip if already done
            if monthProgress.status == .done {
                continue
            }

            let year = monthProgress.year
            let month = monthProgress.month
            let daysInMonth = monthProgress.daysInMonth

            // Collect samples and workouts for this month
            var allBatches: [DaySamples] = []

            do {
                let sampleResult = try await hkCollector.collectSamplesForMonth(year: year, month: month)
                allBatches.append(contentsOf: sampleResult.batches)
            } catch {
                print("[SyncManager] Failed to collect samples for \(year)-\(month): \(error)")
            }

            do {
                let workoutBatches = try await hkCollector.collectWorkoutsForMonth(year: year, month: month)
                allBatches.append(contentsOf: workoutBatches)
            } catch {
                print("[SyncManager] Failed to collect workouts for \(year)-\(month): \(error)")
            }

            // Group batches by day number
            let calendar = Calendar(identifier: .gregorian)
            var batchesByDay: [Int: [DaySamples]] = [:]
            for batch in allBatches {
                let day = calendar.component(.day, from: batch.date)
                batchesByDay[day, default: []].append(batch)
            }

            // Process each day 1...daysInMonth
            for day in 1...daysInMonth {
                guard !Task.isCancelled else {
                    state = .idle
                    return
                }

                // Skip if already done (from restored progress)
                if fullSyncProgress!.months[monthIndex].dayStatuses[day] == .done {
                    continue
                }

                // Mark day as syncing
                fullSyncProgress!.months[monthIndex].dayStatuses[day] = .syncing

                guard let dayBatches = batchesByDay[day], !dayBatches.isEmpty else {
                    // No data for this day — mark done
                    fullSyncProgress!.months[monthIndex].dayStatuses[day] = .done
                    continue
                }

                // Upload each batch for this day
                var dayHasError = false
                for batch in dayBatches {
                    guard !Task.isCancelled else {
                        state = .idle
                        return
                    }

                    // Watermark check: skip if file hasn't changed
                    if !watermark.hasChanged(path: batch.uploadPath, data: batch.data) {
                        totalSkipped += 1
                        continue
                    }

                    do {
                        try await APIClient.shared.saveRawFile(
                            path: batch.uploadPath,
                            data: batch.data
                        )
                        watermark.recordUpload(path: batch.uploadPath, data: batch.data)
                        await hkCollector.commitAnchor(for: batch)
                        totalUploaded += 1
                    } catch {
                        dayHasError = true
                        failures["\(hkCollector.id)/\(batch.uploadPath)"] = error.localizedDescription
                    }
                }

                // Mark day done or error
                if dayHasError {
                    fullSyncProgress!.months[monthIndex].dayStatuses[day] = .error("Upload failed")
                } else {
                    fullSyncProgress!.months[monthIndex].dayStatuses[day] = .done
                }
            }

            // After all days in a month, if month is done, persist to UserDefaults
            if fullSyncProgress!.months[monthIndex].status == .done {
                var completedKeys = Set(
                    UserDefaults.standard.stringArray(forKey: Self.completedMonthsKey) ?? []
                )
                completedKeys.insert(fullSyncProgress!.months[monthIndex].id)
                UserDefaults.standard.set(Array(completedKeys), forKey: Self.completedMonthsKey)
            }
        }

        // Finalize
        if !failures.isEmpty {
            lastError = SyncError(failures: failures)
        }

        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "sync.lastSyncDate")

        let errorCount = failures.count
        if totalUploaded > 0 && errorCount == 0 {
            lastSyncResult = .success(fileCount: totalUploaded)
        } else if totalUploaded > 0 && errorCount > 0 {
            lastSyncResult = .partial(uploaded: totalUploaded, failed: errorCount)
        } else if errorCount > 0 {
            lastSyncResult = .failed(errors: errorCount)
        } else {
            lastSyncResult = .noNewData
        }

        state = .idle
    }

    /// Clears all full sync progress, including persisted completed months.
    @MainActor
    func clearFullSyncProgress() {
        fullSyncProgress = nil
        UserDefaults.standard.removeObject(forKey: Self.completedMonthsKey)
    }
}
