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
