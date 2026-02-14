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

    // MARK: - Configuration

    /// Minimum interval between syncs (seconds)
    private let throttleInterval: TimeInterval = 300  // 5 minutes

    // MARK: - Private

    @ObservationIgnored
    private var collectors: [DataCollector] = []

    @ObservationIgnored
    private var syncTask: Task<Void, Never>?

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
        guard state != .syncing else { return }

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

    /// Cancel any in-progress sync
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
    private func performSync() async {
        state = .syncing
        lastError = nil

        var uploadedCount = 0
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
                let result = try await collector.collectNewSamples()
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

                    do {
                        try await APIClient.shared.saveRawFile(
                            path: batch.uploadPath,
                            data: batch.data
                        )

                        // 3. Commit anchor ONLY after successful upload
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
}
