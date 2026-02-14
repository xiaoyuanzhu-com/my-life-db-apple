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
    /// Number of upload failures
    let filesFailed: Int
    /// Number of collectors that had enabled sources
    let collectorsRun: Int
    /// Whether HealthKit authorization was requested during this sync
    let authorizationRequested: Bool
}
