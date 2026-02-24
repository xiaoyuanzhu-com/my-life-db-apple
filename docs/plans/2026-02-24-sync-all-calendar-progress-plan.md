# Sync All Calendar Grid Progress — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the opaque "Sync All" spinner with a month-chunked sync engine and a full-page calendar grid that shows date numbers turning green progressively.

**Architecture:** New `FullSyncProgress` model tracks per-day status across a year-month hierarchy. `HealthKitCollector` gains a month-scoped query method. `SyncManager` orchestrates month-by-month, updating the observable model after each day. A new `SyncDataView` renders the calendar grid. `DataCollectView` changes "Sync All" to a secondary NavigationLink.

**Tech Stack:** Swift, SwiftUI, HealthKit, UserDefaults (persistence), Swift Testing framework

**Design doc:** `docs/plans/2026-02-24-sync-all-calendar-progress-design.md`

---

### Task 1: Full Sync Progress Model — Types & Tests

Add the data model that tracks per-day sync status and rolls up to month/year level.

**Files:**
- Modify: `MyLifeDB/DataCollect/SyncState.swift` (append after line 71)
- Create: `MyLifeDBTests/FullSyncProgressTests.swift`

**Step 1: Write the failing tests**

Create `MyLifeDBTests/FullSyncProgressTests.swift`:

```swift
//
//  FullSyncProgressTests.swift
//  MyLifeDBTests
//

import Testing
import Foundation
@testable import MyLifeDB

struct FullSyncProgressTests {

    // MARK: - DaySyncStatus

    @Test func daySyncStatusDefaultIsPending() {
        let status = DaySyncStatus.pending
        #expect(status == .pending)
    }

    // MARK: - MonthProgress

    @Test func monthProgressAggregatesStatus() {
        var month = MonthProgress(year: 2024, month: 1)
        // All pending → overall pending
        #expect(month.status == .pending)

        // Mark some days done
        month.dayStatuses[1] = .done
        month.dayStatuses[2] = .done
        // Mix of done and pending → still pending overall (not all done)
        #expect(month.status == .pending)

        // Mark all 31 days done
        for d in 1...31 { month.dayStatuses[d] = .done }
        #expect(month.status == .done)
    }

    @Test func monthProgressDetectsError() {
        var month = MonthProgress(year: 2024, month: 3)
        for d in 1...31 { month.dayStatuses[d] = .done }
        month.dayStatuses[15] = .error("upload failed")
        #expect(month.status == .error)
    }

    @Test func monthProgressDetectsActive() {
        var month = MonthProgress(year: 2024, month: 6)
        month.dayStatuses[1] = .done
        month.dayStatuses[2] = .syncing
        #expect(month.status == .active)
    }

    @Test func monthProgressDaysInMonth() {
        let feb2024 = MonthProgress(year: 2024, month: 2)
        #expect(feb2024.daysInMonth == 29) // leap year

        let feb2025 = MonthProgress(year: 2025, month: 2)
        #expect(feb2025.daysInMonth == 28)

        let jan = MonthProgress(year: 2024, month: 1)
        #expect(jan.daysInMonth == 31)
    }

    @Test func monthProgressFirstWeekday() {
        // Jan 1, 2024 is Monday (weekday 1 in Mon-based calendar)
        let jan2024 = MonthProgress(year: 2024, month: 1)
        #expect(jan2024.firstWeekday == 1) // Monday = 1

        // Feb 1, 2024 is Thursday
        let feb2024 = MonthProgress(year: 2024, month: 2)
        #expect(feb2024.firstWeekday == 4) // Thursday = 4
    }

    // MARK: - FullSyncProgress

    @Test func fullSyncProgressBuildsMonths() {
        let progress = FullSyncProgress(
            startYear: 2024, startMonth: 11,
            endYear: 2025, endMonth: 2
        )
        // Should have: 2024-11, 2024-12, 2025-01, 2025-02
        #expect(progress.months.count == 4)
        #expect(progress.months[0].year == 2024)
        #expect(progress.months[0].month == 11)
        #expect(progress.months[3].year == 2025)
        #expect(progress.months[3].month == 2)
    }

    @Test func fullSyncProgressYearStatus() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        #expect(progress.yearStatus(2024) == .pending)

        // Mark all days in all 3 months as done
        for i in progress.months.indices {
            for d in 1...progress.months[i].daysInMonth {
                progress.months[i].dayStatuses[d] = .done
            }
        }
        #expect(progress.yearStatus(2024) == .done)
    }

    @Test func fullSyncProgressYears() {
        let progress = FullSyncProgress(
            startYear: 2022, startMonth: 6,
            endYear: 2024, endMonth: 3
        )
        #expect(progress.years == [2022, 2023, 2024])
    }

    // MARK: - Persistence

    @Test func fullSyncProgressCompletedMonthsPersistence() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        // Mark January fully done
        for d in 1...31 { progress.months[0].dayStatuses[d] = .done }

        let completed = progress.completedMonthKeys
        #expect(completed.contains("2024-01"))
        #expect(!completed.contains("2024-02"))
    }

    @Test func fullSyncProgressRestoreFromCompleted() {
        var progress = FullSyncProgress(
            startYear: 2024, startMonth: 1,
            endYear: 2024, endMonth: 3
        )
        progress.restoreCompleted(Set(["2024-01", "2024-02"]))

        #expect(progress.months[0].status == .done)
        #expect(progress.months[1].status == .done)
        #expect(progress.months[2].status == .pending)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/FullSyncProgressTests 2>&1 | tail -20`
Expected: Compilation errors — types don't exist yet.

**Step 3: Implement the model**

Append to `MyLifeDB/DataCollect/SyncState.swift` after line 71:

```swift

// MARK: - Full Sync Progress Model

/// Status of a single day's sync
enum DaySyncStatus: Equatable {
    case pending
    case syncing
    case done
    case error(String)
}

/// Aggregate status for a month or year header
enum AggregateStatus: Equatable {
    case pending   // all children pending
    case active    // at least one syncing or mix of done+pending
    case done      // all children done
    case error     // at least one child has error
}

/// Tracks sync progress for a single calendar month
struct MonthProgress: Identifiable {
    let year: Int
    let month: Int

    /// Day number (1-31) → status. Missing keys are pending.
    var dayStatuses: [Int: DaySyncStatus] = [:]

    var id: String { String(format: "%04d-%02d", year, month) }

    /// Number of days in this month
    var daysInMonth: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let components = DateComponents(year: year, month: month)
        guard let date = cal.date(from: components) else { return 30 }
        return cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// Weekday of the 1st (1=Monday, 7=Sunday)
    var firstWeekday: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let components = DateComponents(year: year, month: month, day: 1)
        guard let date = cal.date(from: components) else { return 1 }
        // .weekday: 1=Sun, 2=Mon, ..., 7=Sat
        // Convert to Mon=1, ..., Sun=7
        let wd = cal.component(.weekday, from: date)
        return wd == 1 ? 7 : wd - 1
    }

    /// Aggregate status based on all days in the month
    var status: AggregateStatus {
        let total = daysInMonth
        var doneCount = 0
        var hasError = false
        var hasActive = false

        for day in 1...total {
            switch dayStatuses[day] ?? .pending {
            case .done: doneCount += 1
            case .error: hasError = true
            case .syncing: hasActive = true
            case .pending: break
            }
        }

        if hasError { return .error }
        if doneCount == total { return .done }
        if hasActive || doneCount > 0 { return .active }
        return .pending
    }
}

/// Tracks the full sync session across all months in the date range
struct FullSyncProgress {
    var months: [MonthProgress]

    init(startYear: Int, startMonth: Int, endYear: Int, endMonth: Int) {
        var result: [MonthProgress] = []
        var y = startYear
        var m = startMonth
        while y < endYear || (y == endYear && m <= endMonth) {
            result.append(MonthProgress(year: y, month: m))
            m += 1
            if m > 12 { m = 1; y += 1 }
        }
        months = result
    }

    /// All distinct years
    var years: [Int] {
        Array(Set(months.map(\.year))).sorted()
    }

    /// Months for a given year
    func months(for year: Int) -> [MonthProgress] {
        months.filter { $0.year == year }
    }

    /// Aggregate status for a year
    func yearStatus(_ year: Int) -> AggregateStatus {
        let yearMonths = months.filter { $0.year == year }
        let statuses = yearMonths.map(\.status)
        if statuses.contains(.error) { return .error }
        if statuses.allSatisfy({ $0 == .done }) { return .done }
        if statuses.contains(.active) || statuses.contains(.done) { return .active }
        return .pending
    }

    /// Month keys that are fully completed (for persistence)
    var completedMonthKeys: Set<String> {
        Set(months.filter { $0.status == .done }.map(\.id))
    }

    /// Restore completed months from persisted keys (marks all days as .done)
    mutating func restoreCompleted(_ keys: Set<String>) {
        for i in months.indices where keys.contains(months[i].id) {
            for d in 1...months[i].daysInMonth {
                months[i].dayStatuses[d] = .done
            }
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/FullSyncProgressTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/SyncState.swift MyLifeDBTests/FullSyncProgressTests.swift
git commit -m "feat: add FullSyncProgress model with per-day status tracking

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Month-Scoped HealthKit Query

Add a method to `HealthKitCollector` that queries samples for a single month's date range, plus a discovery method to find the earliest available data.

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift`

**Step 1: Add `querySamples` overload with `until` parameter**

In `HealthKitCollector.swift`, replace lines 698-720 (`querySamples`) with a version that accepts an optional `until` date:

```swift
    private func querySamples(
        type: HKSampleType,
        since startDate: Date,
        until endDate: Date = Date()
    ) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: results ?? [])
                }
            }
            store.execute(query)
        }
    }
```

**Step 2: Add `discoverDateRange` method**

After the `querySamples` method, add:

```swift
    /// Finds the earliest sample date across all enabled types.
    /// Used by full sync to determine the calendar range.
    func discoverDateRange() async -> (start: Date, end: Date)? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let enabled = enabledSourceIDs
        guard !enabled.isEmpty else { return nil }

        let types = allHKTypes(for: enabled)
        var earliest: Date?

        for type in types {
            do {
                let samples = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKSample], Error>) in
                    let q = HKSampleQuery(
                        sampleType: type,
                        predicate: nil,
                        limit: 1,
                        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
                    ) { _, results, error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: results ?? []) }
                    }
                    store.execute(q)
                }
                if let first = samples.first?.startDate {
                    if earliest == nil || first < earliest! {
                        earliest = first
                    }
                }
            } catch {
                continue
            }
        }

        guard let start = earliest else { return nil }
        return (start, Date())
    }
```

**Step 3: Add `collectSamplesForMonth` method**

After `discoverDateRange`, add:

```swift
    /// Collects all samples for a single month and returns batches grouped by (day, type).
    /// This is the month-chunked alternative to `collectNewSamples(fullSync: true)`.
    func collectSamplesForMonth(year: Int, month: Int) async throws -> CollectionResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CollectorError.frameworkUnavailable("HealthKit is not available on this device")
        }

        let enabled = enabledSourceIDs
        guard !enabled.isEmpty else {
            throw CollectorError.noEnabledSources
        }

        let typesToQuery = allHKTypes(for: enabled)

        // Build date range for this month
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        guard let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else {
            return CollectionResult(batches: [], stats: CollectionStats(typesQueried: 0, typesWithData: 0, samplesCollected: 0))
        }

        var allRawSamples: [RawHealthSample] = []
        var typesWithData = 0

        for type in typesToQuery {
            do {
                let samples = try await querySamples(type: type, since: monthStart, until: monthEnd)
                let rawSamples = samples.compactMap { encodeSample($0) }
                if !rawSamples.isEmpty {
                    typesWithData += 1
                }
                allRawSamples.append(contentsOf: rawSamples)
            } catch {
                print("[HealthKitCollector] Failed to query \(type.identifier) for \(year)-\(month): \(error)")
            }
        }

        let stats = CollectionStats(
            typesQueried: typesToQuery.count,
            typesWithData: typesWithData,
            samplesCollected: allRawSamples.count
        )

        guard !allRawSamples.isEmpty else {
            return CollectionResult(batches: [], stats: stats)
        }

        // Group by (day, HK type) — reuse same logic as collectNewSamples
        struct GroupInfo {
            var dayKey: SampleDayBucket.DayKey
            var type: String
            var unit: String?
            var samples: [RawHealthSample]
        }
        var grouped: [String: GroupInfo] = [:]

        for sample in allRawSamples {
            let dayKey = SampleDayBucket.dayKey(sampleStart: sample.start, metadata: sample.metadata)

            let fileBase: String
            if sample.type == "HKWorkoutTypeIdentifier",
               let meta = sample.metadata,
               let activityName = meta["workoutActivityType"] as? String {
                fileBase = HKTypeFileName.workoutFileName(activityName: activityName)
            } else {
                fileBase = HKTypeFileName.fileName(for: sample.type)
            }

            let key = "\(dayKey.date)/\(fileBase)"

            if grouped[key] == nil {
                grouped[key] = GroupInfo(dayKey: dayKey, type: sample.type, unit: sample.unit, samples: [])
            }
            grouped[key]!.samples.append(sample)
        }

        var batches: [DaySamples] = []

        for (key, group) in grouped.sorted(by: { $0.key < $1.key }) {
            let payload = TypeDayPayload(
                type: group.type,
                date: group.dayKey.date,
                timezone: group.dayKey.timezone,
                unit: group.unit,
                samples: group.samples
            )

            guard let jsonData = try? TypeDayPayload.encode(payload) else {
                continue
            }

            let pathComponents = group.dayKey.date.split(separator: "-")
            guard pathComponents.count == 3 else { continue }
            let fileBase = key.split(separator: "/").last!
            let uploadPath = "imports/fitness/apple-health/\(pathComponents[0])/\(pathComponents[1])/\(pathComponents[2])/\(fileBase).json"

            let dayDate = dayDateFormatter.date(from: group.dayKey.date) ?? Date()

            batches.append(DaySamples(
                date: dayDate,
                collectorID: id,
                uploadPath: uploadPath,
                data: jsonData,
                anchorToken: group.samples.map(\.end).max() ?? group.samples.map(\.start).max()
            ))
        }

        return CollectionResult(batches: batches, stats: stats)
    }
```

**Step 4: Build to verify compilation**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift
git commit -m "feat: add month-scoped HealthKit query and date range discovery

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Full Sync Orchestration in SyncManager

Add a new `performFullSync()` method that iterates months, updates `FullSyncProgress`, and persists completed months.

**Files:**
- Modify: `MyLifeDB/DataCollect/SyncManager.swift`

**Step 1: Add observable properties**

After line 40 (`lastSyncDetail`), add:

```swift
    /// Per-day progress for full sync (nil when not doing full sync)
    private(set) var fullSyncProgress: FullSyncProgress?

    /// Whether a full sync has prior progress that can be resumed
    var hasResumableFullSync: Bool {
        let keys = UserDefaults.standard.stringArray(forKey: "sync.fullSync.completedMonths") ?? []
        return !keys.isEmpty
    }
```

**Step 2: Modify `syncAll()` to call new method**

Replace lines 108-117 (`syncAll` method) with:

```swift
    /// Trigger a full sync of all HealthKit history.
    /// - Parameter startImmediately: When false, only builds the calendar model without starting sync.
    @MainActor
    func syncAll(startImmediately: Bool = true) {
        guard state == .idle else { return }
        guard AuthManager.shared.isAuthenticated else { return }

        syncTask?.cancel()
        syncTask = Task {
            await performFullSync()
        }
    }

    /// Build the calendar model for full sync preview (without starting sync).
    @MainActor
    func prepareFullSync() async {
        guard let hkCollector = collectors.first(where: { $0.id == "healthkit" }) as? HealthKitCollector else { return }

        // Discover date range
        guard let range = await hkCollector.discoverDateRange() else { return }

        let cal = Calendar(identifier: .gregorian)
        let startComps = cal.dateComponents([.year, .month], from: range.start)
        let endComps = cal.dateComponents([.year, .month], from: range.end)

        guard let sy = startComps.year, let sm = startComps.month,
              let ey = endComps.year, let em = endComps.month else { return }

        var progress = FullSyncProgress(startYear: sy, startMonth: sm, endYear: ey, endMonth: em)

        // Restore previously completed months
        let completedKeys = Set(UserDefaults.standard.stringArray(forKey: "sync.fullSync.completedMonths") ?? [])
        if !completedKeys.isEmpty {
            progress.restoreCompleted(completedKeys)
        }

        fullSyncProgress = progress
    }
```

**Step 3: Add `performFullSync` method**

After `cancelSync()` (line 124), add:

```swift
    @MainActor
    private func performFullSync() async {
        guard let hkCollector = collectors.first(where: { $0.id == "healthkit" }) as? HealthKitCollector else { return }

        state = .syncingAll
        lastError = nil

        // Build calendar model if not already built
        if fullSyncProgress == nil {
            await prepareFullSync()
        }
        guard var progress = fullSyncProgress else {
            state = .idle
            return
        }

        // Authorization check
        let authStatus = hkCollector.authorizationStatus()
        if authStatus == .notDetermined {
            let granted = await hkCollector.requestAuthorization()
            if !granted {
                state = .idle
                return
            }
        } else if authStatus == .denied || authStatus == .restricted || authStatus == .unavailable {
            state = .idle
            return
        }

        var totalUploaded = 0
        var totalSkipped = 0
        var failures: [String: String] = [:]

        // Iterate months oldest first
        for monthIndex in progress.months.indices {
            guard !Task.isCancelled else { break }

            let mp = progress.months[monthIndex]

            // Skip already-completed months
            if mp.status == .done { continue }

            // Collect samples for this month
            do {
                let result = try await hkCollector.collectSamplesForMonth(year: mp.year, month: mp.month)

                // Group batches by day number
                let cal = Calendar(identifier: .gregorian)
                var batchesByDay: [Int: [DaySamples]] = [:]
                for batch in result.batches {
                    let day = cal.component(.day, from: batch.date)
                    batchesByDay[day, default: []].append(batch)
                }

                // Process each day in order
                for day in 1...mp.daysInMonth {
                    guard !Task.isCancelled else { break }

                    // Skip already-done days (from restored progress)
                    if progress.months[monthIndex].dayStatuses[day] == .done { continue }

                    progress.months[monthIndex].dayStatuses[day] = .syncing
                    fullSyncProgress = progress

                    guard let dayBatches = batchesByDay[day] else {
                        // No data for this day — mark done
                        progress.months[monthIndex].dayStatuses[day] = .done
                        fullSyncProgress = progress
                        continue
                    }

                    var dayFailed = false
                    for batch in dayBatches {
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
                            dayFailed = true
                            failures[batch.uploadPath] = error.localizedDescription
                        }
                    }

                    progress.months[monthIndex].dayStatuses[day] = dayFailed
                        ? .error("Upload failed")
                        : .done
                    fullSyncProgress = progress
                }

                // Persist completed month
                if progress.months[monthIndex].status == .done {
                    var completedKeys = Set(UserDefaults.standard.stringArray(forKey: "sync.fullSync.completedMonths") ?? [])
                    completedKeys.insert(mp.id)
                    UserDefaults.standard.set(Array(completedKeys), forKey: "sync.fullSync.completedMonths")
                }

            } catch {
                // Month-level failure — mark all remaining days as error
                for day in 1...mp.daysInMonth {
                    if progress.months[monthIndex].dayStatuses[day] == nil
                        || progress.months[monthIndex].dayStatuses[day] == .pending {
                        progress.months[monthIndex].dayStatuses[day] = .error(error.localizedDescription)
                    }
                }
                fullSyncProgress = progress
                failures[mp.id] = error.localizedDescription
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
```

**Step 4: Build to verify compilation**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 5: Run all existing tests to ensure no regressions**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 6: Commit**

```bash
git add MyLifeDB/DataCollect/SyncManager.swift
git commit -m "feat: add month-by-month full sync orchestration with progress tracking

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Calendar Grid SwiftUI Component

Build the core calendar grid view — the Mon–Sun date layout where numbers turn green.

**Files:**
- Create: `MyLifeDB/Views/Me/SyncCalendarGrid.swift`

**Step 1: Create the calendar grid component**

Create `MyLifeDB/Views/Me/SyncCalendarGrid.swift`:

```swift
//
//  SyncCalendarGrid.swift
//  MyLifeDB
//
//  Calendar grid component for the full sync progress view.
//  Shows date numbers in a Mon–Sun layout. Numbers turn green
//  progressively as each day syncs.
//

import SwiftUI

// MARK: - Month Calendar Grid

struct MonthCalendarGrid: View {
    let month: MonthProgress

    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Month header with status dot
            HStack(spacing: 6) {
                Text(monthName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                statusDot(for: month.status)
            }
            .padding(.bottom, 2)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Date numbers
            LazyVGrid(columns: columns, spacing: 4) {
                // Empty cells before the 1st
                ForEach(0..<(month.firstWeekday - 1), id: \.self) { _ in
                    Text("")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }

                // Day numbers
                ForEach(1...month.daysInMonth, id: \.self) { day in
                    dayCell(day: day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(day: Int) -> some View {
        let status = month.dayStatuses[day] ?? .pending

        Text("\(day)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(dayColor(for: status))
            .frame(maxWidth: .infinity, minHeight: 28)
            .opacity(status == .pending ? 0.3 : 1.0)
            .overlay {
                if status == .syncing {
                    // Subtle pulsing ring
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                        .frame(width: 24, height: 24)
                        .modifier(PulseAnimation())
                }
            }
    }

    private func dayColor(for status: DaySyncStatus) -> Color {
        switch status {
        case .pending: return .primary
        case .syncing: return .accentColor
        case .done: return .green
        case .error: return .red
        }
    }

    @ViewBuilder
    private func statusDot(for status: AggregateStatus) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .active:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .modifier(PulseAnimation())
        case .done:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
        }
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let components = DateComponents(year: month.year, month: month.month, day: 1)
        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Year Section

struct YearSection: View {
    let year: Int
    let months: [MonthProgress]
    let yearStatus: AggregateStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Year header
            HStack(spacing: 6) {
                Text(String(year))
                    .font(.title3)
                    .fontWeight(.semibold)
                yearStatusDot
            }

            // All months for this year
            ForEach(months) { month in
                MonthCalendarGrid(month: month)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var yearStatusDot: some View {
        switch yearStatus {
        case .pending:
            EmptyView()
        case .active:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .modifier(PulseAnimation())
        case .done:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
```

**Step 2: Build to verify compilation**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add MyLifeDB/Views/Me/SyncCalendarGrid.swift
git commit -m "feat: add calendar grid component for full sync progress

Mon-Sun layout with date numbers that turn green progressively.
Minimal design: text color for status, small dots for headers.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: SyncDataView — Full Page

Create the full-page view that shows the header, start/resume button, and the calendar grid.

**Files:**
- Create: `MyLifeDB/Views/Me/SyncDataView.swift`

**Step 1: Create the view**

Create `MyLifeDB/Views/Me/SyncDataView.swift`:

```swift
//
//  SyncDataView.swift
//  MyLifeDB
//
//  Full-page view for "Sync All History". Shows a calendar grid
//  with per-day progress. User navigates here from DataCollectView,
//  then taps Start to begin the sync.
//

import SwiftUI

struct SyncDataView: View {
    private var syncManager = SyncManager.shared
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                    .padding(.horizontal)

                if isLoading {
                    ProgressView("Discovering data range...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if let progress = syncManager.fullSyncProgress {
                    calendarSection(progress)
                        .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        "No Health Data",
                        systemImage: "heart.text.clipboard",
                        description: Text("Enable health data sources in Data Collect to sync.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Health Data Sync")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if syncManager.fullSyncProgress == nil {
                await syncManager.prepareFullSync()
            }
            isLoading = false
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let progress = syncManager.fullSyncProgress {
                // Summary line
                let typeCount = HealthKitCollector().enabledSourceIDs.count
                let yearRange = progress.years
                if let first = yearRange.first, let last = yearRange.last {
                    Text("\(typeCount) types · \(first)–\(last)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Action button
                HStack {
                    Spacer()
                    syncButton
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var syncButton: some View {
        switch syncManager.state {
        case .syncingAll:
            Button {
                syncManager.cancelSync()
            } label: {
                Text("Pause")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)

        case .idle:
            let hasResumable = syncManager.hasResumableFullSync
            Button {
                syncManager.syncAll()
            } label: {
                Text(hasResumable ? "Resume" : "Start")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)

            // Retry button if there are errors
            if let progress = syncManager.fullSyncProgress,
               progress.months.contains(where: { $0.status == .error }) {
                Button {
                    retryFailed()
                } label: {
                    Text("Retry Failed")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private func calendarSection(_ progress: FullSyncProgress) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(progress.years, id: \.self) { year in
                YearSection(
                    year: year,
                    months: progress.months(for: year),
                    yearStatus: progress.yearStatus(year)
                )
            }
        }
    }

    // MARK: - Actions

    private func retryFailed() {
        // Clear error states back to pending so they're re-attempted
        guard var progress = syncManager.fullSyncProgress else { return }
        for i in progress.months.indices {
            for day in 1...progress.months[i].daysInMonth {
                if case .error = progress.months[i].dayStatuses[day] {
                    progress.months[i].dayStatuses[day] = .pending
                }
            }
        }
        syncManager.fullSyncProgress = progress
        syncManager.syncAll()
    }
}
```

**Step 2: Make `fullSyncProgress` settable for retry**

In `SyncManager.swift`, change the `fullSyncProgress` property from:
```swift
    private(set) var fullSyncProgress: FullSyncProgress?
```
to:
```swift
    var fullSyncProgress: FullSyncProgress?
```

(The `@Observable` macro handles change tracking; external writes trigger view updates.)

**Step 3: Build to verify compilation**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MyLifeDB/Views/Me/SyncDataView.swift MyLifeDB/DataCollect/SyncManager.swift
git commit -m "feat: add SyncDataView with calendar grid and start/pause controls

Full-page view navigated from DataCollectView. Shows year sections
with month calendar grids. Start/Resume/Pause buttons.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 6: DataCollectView — Button Layout Change

Move "Sync All History" from a side-by-side button to a secondary NavigationLink on a second line.

**Files:**
- Modify: `MyLifeDB/Views/Me/DataCollectView.swift` (lines 308-370)

**Step 1: Replace the sync section**

Replace lines 308-370 (the entire `Section { ... } header: { ... }`) with:

```swift
            // Sync status section
            Section {
                // Row 1: Status + Sync Now button
                HStack {
                    if syncManager.state == .syncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                            .foregroundStyle(.secondary)
                    } else if syncManager.state == .syncingAll {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing all history...")
                            .foregroundStyle(.secondary)
                    } else if let lastSync = syncManager.lastSyncDate {
                        syncResultIcon
                            .font(.caption)
                        Text(syncStatusText(lastSync: lastSync))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Not synced yet")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        syncManager.sync(force: true)
                    } label: {
                        Text("Sync Now")
                            .font(.subheadline)
                    }
                    .disabled(syncManager.state != .idle)
                }

                // Row 2: Sync All History → navigates to SyncDataView
                NavigationLink {
                    SyncDataView()
                } label: {
                    HStack {
                        Text("Sync All History")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                // Detailed sync breakdown
                if let detail = syncManager.lastSyncDetail, syncManager.state == .idle {
                    syncDetailView(detail)
                }

                if let error = syncManager.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(error.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
```

**Step 2: Build to verify compilation**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 3: Run all tests**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 4: Commit**

```bash
git add MyLifeDB/Views/Me/DataCollectView.swift
git commit -m "feat: move Sync All History to secondary NavigationLink

Sync Now remains the primary action. Sync All History is now a
navigation link on a second line, opening the new SyncDataView.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Workout Collection Integration

The current full sync also collects workouts separately. We need to integrate workout collection into the month-chunked flow.

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift`
- Modify: `MyLifeDB/DataCollect/SyncManager.swift`

**Step 1: Add month-scoped workout collection**

In `HealthKitCollector.swift`, add after `collectSamplesForMonth`:

```swift
    /// Collects workouts for a single month, including GPS routes.
    func collectWorkoutsForMonth(year: Int, month: Int) async throws -> [DaySamples] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        guard let monthStart = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: monthStart, end: monthEnd, options: .strictStartDate
        )

        let workouts = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKSample], Error>) in
            let q = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: results ?? []) }
            }
            store.execute(q)
        }

        var batches: [DaySamples] = []
        let deviceInfo = currentDeviceInfo()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        for sample in workouts {
            guard let workout = sample as? HKWorkout else { continue }

            let uuid = workout.uuid.uuidString
            let activityType = workoutActivityTypeName(for: workout.workoutActivityType.rawValue)

            var stats: [String: StatValue] = [:]
            if let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                stats["active_energy_burned"] = StatValue(value: energy.doubleValue(for: .kilocalorie()), unit: "kcal")
            }
            if let dist = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() {
                stats["distance"] = StatValue(value: dist.doubleValue(for: .meter()), unit: "m")
            }
            if let strokes = workout.statistics(for: HKQuantityType(.swimmingStrokeCount))?.sumQuantity() {
                stats["swimming_stroke_count"] = StatValue(value: strokes.doubleValue(for: .count()), unit: "count")
            }

            let route = try? await fetchRoute(for: workout)

            let workoutFile = WorkoutFile(
                uuid: uuid,
                activityType: activityType,
                start: workout.startDate,
                end: workout.endDate,
                durationS: workout.duration,
                source: workout.sourceRevision.source.bundleIdentifier,
                device: workout.sourceRevision.productType ?? workout.device?.name,
                syncedAt: Date(),
                deviceInfo: deviceInfo,
                stats: stats,
                metadata: encodeMetadata(workout.metadata),
                route: route
            )

            guard let jsonData = try? encoder.encode(workoutFile) else { continue }

            let components = cal.dateComponents([.year, .month, .day], from: workout.startDate)
            guard let y = components.year, let mo = components.month, let d = components.day else { continue }
            let uploadPath = String(format: "imports/fitness/apple-health/%04d/%02d/%02d/workout-%@.json",
                                    y, mo, d, uuid)

            batches.append(DaySamples(
                date: workout.startDate,
                collectorID: id,
                uploadPath: uploadPath,
                data: jsonData,
                anchorToken: workout.endDate
            ))
        }

        return batches
    }
```

**Step 2: Integrate workouts into `performFullSync`**

In `SyncManager.swift`, inside `performFullSync()`, after the line that calls `collectSamplesForMonth`, add workout batches to the same processing. Find the `let result = try await hkCollector.collectSamplesForMonth(...)` line and add workout collection after it:

```swift
                // Also collect workouts for this month
                let workoutBatches = try await hkCollector.collectWorkoutsForMonth(year: mp.year, month: mp.month)

                // Merge workout batches into batchesByDay
                for batch in workoutBatches {
                    let day = cal.component(.day, from: batch.date)
                    batchesByDay[day, default: []].append(batch)
                }
```

Place this right after building `batchesByDay` from `result.batches` and before the "Process each day in order" loop.

**Step 3: Build**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift MyLifeDB/DataCollect/SyncManager.swift
git commit -m "feat: integrate workout collection into month-chunked sync

Workouts with GPS routes are now collected per-month alongside
regular health samples during full sync.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 8: Clear Full Sync Progress

Add the ability to clear persisted progress (useful for re-syncing everything from scratch).

**Files:**
- Modify: `MyLifeDB/DataCollect/SyncManager.swift`
- Modify: `MyLifeDB/Views/Me/SyncDataView.swift`

**Step 1: Add clearFullSyncProgress to SyncManager**

Add after `prepareFullSync`:

```swift
    /// Clears all full sync progress, allowing a fresh start.
    @MainActor
    func clearFullSyncProgress() {
        fullSyncProgress = nil
        UserDefaults.standard.removeObject(forKey: "sync.fullSync.completedMonths")
    }
```

**Step 2: Add a "Reset" option to SyncDataView**

In `SyncDataView.swift`, add a toolbar button in the `body` view, after `.navigationBarTitleDisplayMode(.inline)`:

```swift
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if syncManager.state == .idle && syncManager.hasResumableFullSync {
                    Menu {
                        Button(role: .destructive) {
                            syncManager.clearFullSyncProgress()
                            isLoading = true
                            Task {
                                await syncManager.prepareFullSync()
                                isLoading = false
                            }
                        } label: {
                            Label("Reset Progress", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
```

**Step 3: Build**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 4: Run all tests**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/SyncManager.swift MyLifeDB/Views/Me/SyncDataView.swift
git commit -m "feat: add reset progress option for full sync

Toolbar menu in SyncDataView allows clearing all progress
to re-sync everything from scratch.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 9: Final Integration & Smoke Test

Verify everything works together end-to-end.

**Step 1: Build the full project**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

**Step 2: Run all tests**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 3: Verify navigation flow**

Launch in simulator and verify:
1. Me tab → Data Collect → Sync section shows "Sync Now" button (primary) and "Sync All History" navigation link (secondary, second line)
2. Tap "Sync All History" → navigates to SyncDataView
3. SyncDataView shows "Discovering data range..." then the calendar grid
4. Start button is visible
5. Back navigation works

**Step 4: No commit needed — this is verification only**

---

## Summary of Files Changed

| Action | File | Description |
|--------|------|-------------|
| Modify | `MyLifeDB/DataCollect/SyncState.swift` | Add `DaySyncStatus`, `AggregateStatus`, `MonthProgress`, `FullSyncProgress` |
| Modify | `MyLifeDB/DataCollect/SyncManager.swift` | Add `fullSyncProgress`, `performFullSync()`, `prepareFullSync()`, `clearFullSyncProgress()` |
| Modify | `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift` | Add `querySamples(until:)`, `discoverDateRange()`, `collectSamplesForMonth()`, `collectWorkoutsForMonth()` |
| Modify | `MyLifeDB/Views/Me/DataCollectView.swift` | Move "Sync All" to NavigationLink on second line |
| Create | `MyLifeDB/Views/Me/SyncCalendarGrid.swift` | Calendar grid component (MonthCalendarGrid, YearSection) |
| Create | `MyLifeDB/Views/Me/SyncDataView.swift` | Full-page sync progress view |
| Create | `MyLifeDBTests/FullSyncProgressTests.swift` | Tests for progress model |
