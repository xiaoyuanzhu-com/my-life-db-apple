//
//  SyncState.swift
//  MyLifeDB
//
//  State types for the sync manager, observable by SwiftUI views.
//

import Foundation

/// Overall sync state
enum SyncState: Equatable {
    case idle
    case syncing
    case syncingAll  // Full history sync in progress
}

/// Per-collector sync state
enum CollectorSyncState: Equatable {
    case idle
    case collecting
    case uploading(progress: Double)  // 0.0 to 1.0
    case error(String)
}

/// Result of the last sync cycle
enum SyncResult: Equatable {
    /// Files were uploaded successfully (all succeeded)
    case success(fileCount: Int)
    /// Sync ran but there was no new data to upload
    case noNewData
    /// Some uploads succeeded but others failed
    case partial(uploaded: Int, failed: Int)
    /// All uploads failed
    case failed(errors: Int)
}

/// Aggregated error from a sync cycle
struct SyncError: Equatable {

    /// Map of "collectorID" or "collectorID/uploadPath" → error message
    let failures: [String: String]

    var summary: String {
        let count = failures.count
        return "\(count) sync error\(count == 1 ? "" : "s")"
    }

    static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        lhs.failures == rhs.failures
    }
}

/// Detailed breakdown of what happened during a sync cycle
struct SyncDetail: Equatable {
    /// Total raw samples collected across all collectors
    let samplesCollected: Int
    /// Number of framework data types queried
    let typesQueried: Int
    /// Number of types that returned data
    let typesWithData: Int
    /// Number of files uploaded to the server
    let filesUploaded: Int
    /// Number of files skipped (unchanged per watermark)
    let filesSkipped: Int
    /// Number of upload failures
    let filesFailed: Int
    /// Number of collectors that had enabled sources
    let collectorsRun: Int
    /// Whether HealthKit authorization was requested during this sync
    let authorizationRequested: Bool
}

// MARK: - Full Sync Progress Model

/// Status of a single day during full-history sync
enum DaySyncStatus: Equatable {
    case pending
    case syncing
    case done
    case error(String)
}

/// Rolled-up status for a month or year
enum AggregateStatus: Equatable {
    case pending
    case active
    case done
    case error
}

/// Tracks per-day sync status for a calendar month
struct MonthProgress: Identifiable {
    let year: Int
    let month: Int
    var dayStatuses: [Int: DaySyncStatus] = [:]

    var id: String {
        String(format: "%04d-%02d", year, month)
    }

    /// Number of days in this calendar month
    var daysInMonth: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        let dc = DateComponents(year: year, month: month)
        guard let date = cal.date(from: dc) else { return 30 }
        return cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    /// Weekday of the 1st of the month (1 = Monday, 7 = Sunday)
    var firstWeekday: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        let dc = DateComponents(year: year, month: month, day: 1)
        guard let date = cal.date(from: dc) else { return 1 }
        // Calendar weekday: 1=Sun, 2=Mon, …, 7=Sat
        let wd = cal.component(.weekday, from: date)
        // Convert to 1=Mon, 2=Tue, …, 7=Sun
        return wd == 1 ? 7 : wd - 1
    }

    /// Aggregate status rolled up from day statuses
    var status: AggregateStatus {
        let total = daysInMonth
        let statuses = (1...total).map { dayStatuses[$0] ?? .pending }

        if statuses.contains(where: {
            if case .error = $0 { return true }
            return false
        }) {
            return .error
        }

        let doneCount = statuses.filter { $0 == .done }.count
        if doneCount == total {
            return .done
        }

        let hasSyncing = statuses.contains { $0 == .syncing }
        if hasSyncing || doneCount > 0 {
            return .active
        }

        return .pending
    }
}

/// Tracks full-history sync progress across a range of months
struct FullSyncProgress {
    var months: [MonthProgress]

    /// Build progress for all months from startYear/startMonth through endYear/endMonth (inclusive)
    init(startYear: Int, startMonth: Int, endYear: Int, endMonth: Int) {
        var result: [MonthProgress] = []
        var y = startYear
        var m = startMonth
        while y < endYear || (y == endYear && m <= endMonth) {
            result.append(MonthProgress(year: y, month: m))
            m += 1
            if m > 12 {
                m = 1
                y += 1
            }
        }
        self.months = result
    }

    /// Sorted distinct years present in the progress range
    var years: [Int] {
        Array(Set(months.map(\.year))).sorted()
    }

    /// All months for a given year, in order
    func months(for year: Int) -> [MonthProgress] {
        months.filter { $0.year == year }
    }

    /// Aggregate status for an entire year, rolled up from its months
    func yearStatus(_ year: Int) -> AggregateStatus {
        let monthStatuses = months(for: year).map(\.status)
        if monthStatuses.isEmpty { return .pending }

        if monthStatuses.contains(.error) { return .error }
        if monthStatuses.allSatisfy({ $0 == .done }) { return .done }
        if monthStatuses.contains(.active) || monthStatuses.contains(.done) { return .active }
        return .pending
    }

    /// Set of month IDs (e.g. "2024-01") where all days are done
    var completedMonthKeys: Set<String> {
        Set(months.filter { $0.status == .done }.map(\.id))
    }

    /// Mark all days as `.done` for months whose IDs appear in `keys`
    mutating func restoreCompleted(_ keys: Set<String>) {
        for i in months.indices where keys.contains(months[i].id) {
            let total = months[i].daysInMonth
            for day in 1...total {
                months[i].dayStatuses[day] = .done
            }
        }
    }
}
