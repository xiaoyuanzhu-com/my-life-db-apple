//
//  CollectorTypes.swift
//  MyLifeDB
//
//  Shared types used by data collectors and the sync manager.
//

import Foundation

/// One day's worth of samples from a collector, ready for upload.
struct DaySamples {

    /// The calendar date this batch covers
    let date: Date

    /// The collector that produced this batch
    let collectorID: String

    /// The upload path on the backend
    /// e.g., "imports/fitness/apple-health/2026/02/09/sample-2026-02-09T12-00-00Z.json"
    /// or    "imports/fitness/apple-health/2026/02/09/workout-E3F2ABCD-….json"
    let uploadPath: String

    /// The JSON data to upload (already encoded)
    let data: Data

    /// Opaque anchor data the collector uses to track progress.
    /// Stored by the collector after successful upload.
    let anchorToken: Any?
}

/// Statistics from a data collection run, reported alongside batches.
struct CollectionStats: Equatable {
    /// Number of framework types queried (e.g., HK sample types)
    let typesQueried: Int
    /// Number of types that returned at least one sample
    let typesWithData: Int
    /// Total number of raw samples collected across all types
    let samplesCollected: Int
}

/// Result of a collector's `collectNewSamples()` call.
struct CollectionResult {
    /// The day-grouped batches ready for upload
    let batches: [DaySamples]
    /// Statistics about what was collected
    let stats: CollectionStats
}

/// Errors specific to data collection
enum CollectorError: LocalizedError {

    /// Framework permission was denied (e.g., "HealthKit access denied")
    case authorizationDenied(String)

    /// Framework not available on this device (e.g., HealthKit on iPad)
    case frameworkUnavailable(String)

    /// All data source toggles are off for this collector
    case noEnabledSources

    /// A specific data type query failed (source ID, underlying error)
    case queryFailed(String, Error)

    /// JSON encoding failed
    case encodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied(let msg):
            return "Permission denied: \(msg)"
        case .frameworkUnavailable(let msg):
            return "Unavailable: \(msg)"
        case .noEnabledSources:
            return "No data sources enabled"
        case .queryFailed(let source, let err):
            return "Failed to query \(source): \(err.localizedDescription)"
        case .encodingFailed(let err):
            return "Failed to encode data: \(err.localizedDescription)"
        }
    }
}
