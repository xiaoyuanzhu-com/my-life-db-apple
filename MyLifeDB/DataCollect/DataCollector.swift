//
//  DataCollector.swift
//  MyLifeDB
//
//  Protocol for data collectors. Each Apple framework (HealthKit, CoreLocation,
//  DeviceActivity, etc.) implements this protocol. SyncManager orchestrates them.
//

import Foundation

/// A data collector gathers samples from a specific Apple framework
/// and prepares them for upload to the backend.
protocol DataCollector {

    /// Unique identifier for this collector (e.g., "healthkit", "location")
    var id: String { get }

    /// Human-readable name for logging and debug UI
    var displayName: String { get }

    /// The DataSource toggle IDs this collector covers.
    /// These match the `DataSource.id` values in DataCollectView
    /// (e.g., ["steps", "heart_rate", "sleep_duration", ...]).
    var sourceIDs: [String] { get }

    /// Which of this collector's sourceIDs are currently enabled by the user.
    var enabledSourceIDs: [String] { get }

    /// Whether any sources are enabled.
    var hasEnabledSources: Bool { get }

    /// Request any necessary permissions (e.g., HealthKit authorization).
    /// Called when sources are first enabled, not on every sync.
    /// Returns true if authorization was granted (even partially).
    func requestAuthorization() async -> Bool

    /// Check current authorization status without prompting.
    func authorizationStatus() -> CollectorAuthStatus

    /// Collect new samples since the last anchor, grouped by day.
    /// Only collects data for enabled sources.
    /// Returns a CollectionResult with batches and stats about what was collected.
    func collectNewSamples() async throws -> CollectionResult

    /// Advance the anchor after successful upload of a batch.
    /// Called by SyncManager ONLY after the upload succeeds.
    func commitAnchor(for batch: DaySamples) async
}

// MARK: - Default Implementations

extension DataCollector {

    var enabledSourceIDs: [String] {
        sourceIDs.filter { UserDefaults.standard.bool(forKey: "dataCollect.\($0)") }
    }

    var hasEnabledSources: Bool {
        !enabledSourceIDs.isEmpty
    }
}

// MARK: - Authorization Status

enum CollectorAuthStatus {
    case notDetermined
    case authorized
    case denied
    case restricted      // parental controls, MDM, etc.
    case unavailable     // framework not available on this device
}
