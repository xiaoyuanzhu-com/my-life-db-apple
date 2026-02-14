//
//  HealthKitCollector.swift
//  MyLifeDB
//
//  Collects health data from HealthKit using anchored queries.
//  Samples are exported raw (no aggregation) and grouped by startDate day.
//

import Foundation
import HealthKit
#if os(iOS)
import UIKit
#endif

final class HealthKitCollector: DataCollector {

    let id = "healthkit"
    let displayName = "Apple Health"

    // MARK: - Source IDs

    /// All DataSource toggle IDs this collector covers.
    /// These match the `DataSource.id` values in DataCollectView.
    let sourceIDs: [String] = [
        // Health & Body
        "steps", "distance", "flights", "active_energy", "exercise_min",
        "stand_hours", "heart_rate", "hrv", "blood_oxygen", "respiratory_rate",
        "vo2max", "body_weight", "walking_steadiness",
        // Sleep
        "sleep_duration", "sleep_stages", "bedtime", "sleep_consistency",
        // Fitness
        "workouts", "running", "swimming", "cycling",
        // Nutrition
        "water", "caffeine", "calories_in",
        // Mindfulness
        "mindful_min", "mood",
    ]

    // MARK: - Private

    private let store = HKHealthStore()

    /// How far back to look on first sync (no anchor yet)
    private let initialLookbackDays = 7

    // MARK: - Source ID → HKSampleType Mapping

    /// Returns the HealthKit sample types needed for a given source ID.
    /// One source ID may map to multiple HK types (e.g., "heart_rate" covers
    /// heartRate, restingHeartRate, walkingHeartRateAverage).
    private func hkTypes(for sourceID: String) -> [HKSampleType] {
        switch sourceID {
        // Health & Body
        case "steps":             return [HKQuantityType(.stepCount)]
        case "distance":          return [HKQuantityType(.distanceWalkingRunning)]
        case "flights":           return [HKQuantityType(.flightsClimbed)]
        case "active_energy":     return [HKQuantityType(.activeEnergyBurned)]
        case "exercise_min":      return [HKQuantityType(.appleExerciseTime)]
        case "stand_hours":       return [HKQuantityType(.appleStandTime)]
        case "heart_rate":        return [
                                      HKQuantityType(.heartRate),
                                      HKQuantityType(.restingHeartRate),
                                      HKQuantityType(.walkingHeartRateAverage),
                                      HKQuantityType(.heartRateRecoveryOneMinute),
                                  ]
        case "hrv":               return [HKQuantityType(.heartRateVariabilitySDNN)]
        case "blood_oxygen":      return [HKQuantityType(.oxygenSaturation)]
        case "respiratory_rate":  return [HKQuantityType(.respiratoryRate)]
        case "vo2max":            return [HKQuantityType(.vo2Max)]
        case "body_weight":       return [HKQuantityType(.bodyMass)]
        case "walking_steadiness": return [HKQuantityType(.appleSleepingWristTemperature)]
            // Note: walkingSteadiness requires a dedicated API, using temperature as placeholder

        // Sleep — all map to the same HK type
        case "sleep_duration", "sleep_stages", "bedtime", "sleep_consistency":
            return [HKCategoryType(.sleepAnalysis)]

        // Fitness
        case "workouts", "running", "swimming", "cycling":
            return [HKWorkoutType.workoutType()]

        // Nutrition
        case "water":         return [HKQuantityType(.dietaryWater)]
        case "caffeine":      return [HKQuantityType(.dietaryCaffeine)]
        case "calories_in":   return [HKQuantityType(.dietaryEnergyConsumed)]

        // Mindfulness
        case "mindful_min":   return [HKCategoryType(.mindfulSession)]
        case "mood":          return [] // iOS 17+ State of Mind, handled separately

        default: return []
        }
    }

    /// All unique HK types needed for the given source IDs.
    private func allHKTypes(for sourceIDs: [String]) -> Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for id in sourceIDs {
            for type in hkTypes(for: id) {
                types.insert(type)
            }
        }
        return types
    }

    /// Preferred unit for a quantity type (used when extracting numeric values).
    private func preferredUnit(for typeID: HKQuantityTypeIdentifier) -> HKUnit {
        switch typeID {
        case .stepCount:                     return .count()
        case .distanceWalkingRunning:         return .meter()
        case .flightsClimbed:                return .count()
        case .activeEnergyBurned:            return .kilocalorie()
        case .basalEnergyBurned:             return .kilocalorie()
        case .appleExerciseTime:             return .minute()
        case .appleStandTime:                return .minute()
        case .heartRate:                     return .count().unitDivided(by: .minute())
        case .restingHeartRate:              return .count().unitDivided(by: .minute())
        case .walkingHeartRateAverage:       return .count().unitDivided(by: .minute())
        case .heartRateRecoveryOneMinute:    return .count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:      return .secondUnit(with: .milli)
        case .oxygenSaturation:              return .percent()
        case .respiratoryRate:               return .count().unitDivided(by: .minute())
        case .vo2Max:                        return HKUnit(from: "ml/kg*min")
        case .bodyMass:                      return .gramUnit(with: .kilo)
        case .bodyFatPercentage:             return .percent()
        case .dietaryWater:                  return .liter()
        case .dietaryCaffeine:               return .gramUnit(with: .milli)
        case .dietaryEnergyConsumed:         return .kilocalorie()
        case .appleSleepingWristTemperature: return .degreeCelsius()
        default:                             return .count()
        }
    }

    // MARK: - Authorization

    /// UserDefaults key tracking which HK type identifiers we've already requested auth for.
    private let authorizedTypesKey = "sync.healthkit.authorizedTypes"

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let readTypes = allHKTypes(for: enabledSourceIDs)
        guard !readTypes.isEmpty else { return false }

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // Accumulate type identifiers we've requested auth for
            // (merge with previously authorized types, don't replace)
            let previouslyAuthorized = Set(
                UserDefaults.standard.stringArray(forKey: authorizedTypesKey) ?? []
            )
            let newTypeIDs = Set(readTypes.map { $0.identifier })
            let allAuthorized = Array(previouslyAuthorized.union(newTypeIDs))
            UserDefaults.standard.set(allAuthorized, forKey: authorizedTypesKey)
            return true
        } catch {
            return false
        }
    }

    func authorizationStatus() -> CollectorAuthStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }
        // HealthKit doesn't expose read authorization status (privacy policy).
        // We track which types we've previously requested auth for.
        // If there are new types we haven't requested yet, return .notDetermined
        // so SyncManager will prompt the user.
        let previouslyAuthorized = Set(
            UserDefaults.standard.stringArray(forKey: authorizedTypesKey) ?? []
        )

        // If we've never requested auth at all, always prompt
        if previouslyAuthorized.isEmpty {
            return .notDetermined
        }

        // Check if current enabled sources need any types we haven't requested yet
        let currentTypes = allHKTypes(for: enabledSourceIDs)
        let currentTypeIDs = Set(currentTypes.map { $0.identifier })
        let newTypes = currentTypeIDs.subtracting(previouslyAuthorized)

        if !newTypes.isEmpty {
            return .notDetermined
        }

        return .authorized
    }

    // MARK: - Data Collection

    func collectNewSamples() async throws -> CollectionResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CollectorError.frameworkUnavailable("HealthKit is not available on this device")
        }

        let enabled = enabledSourceIDs
        guard !enabled.isEmpty else {
            throw CollectorError.noEnabledSources
        }

        // Determine which HK types to query (deduplicate across source IDs)
        let typesToQuery = allHKTypes(for: enabled)

        // Load anchor date (or default to N days ago)
        let anchorDate = loadAnchorDate()
            ?? Calendar.current.date(byAdding: .day, value: -initialLookbackDays, to: Date())!

        // Query each type and collect raw samples, tracking stats
        var allRawSamples: [RawHealthSample] = []
        var typesWithData = 0

        for type in typesToQuery {
            do {
                let samples = try await querySamples(type: type, since: anchorDate)
                let rawSamples = samples.compactMap { encodeSample($0) }
                if !rawSamples.isEmpty {
                    typesWithData += 1
                }
                allRawSamples.append(contentsOf: rawSamples)
            } catch {
                // Per-query failure: log and continue with other types
                print("[HealthKitCollector] Failed to query \(type.identifier): \(error)")
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

        // Group samples by startDate's calendar day
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allRawSamples) { sample -> String in
            let components = calendar.dateComponents([.year, .month, .day], from: sample.start)
            return String(format: "%04d-%02d-%02d",
                          components.year!, components.month!, components.day!)
        }

        // Build DaySamples for each day
        let syncTimestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let deviceInfo = currentDeviceInfo()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        var batches: [DaySamples] = []

        for (dayString, samples) in grouped.sorted(by: { $0.key < $1.key }) {
            let sorted = samples.sorted { $0.start < $1.start }

            let payload = SyncFilePayload(
                syncedAt: Date(),
                deviceInfo: deviceInfo,
                samples: sorted
            )

            guard let jsonData = try? encoder.encode(payload) else {
                continue
            }

            // Path: imports/fitness/apple-health/raw/YYYY/MM/DD/<timestamp>.json
            let pathComponents = dayString.split(separator: "-")
            guard pathComponents.count == 3 else { continue }
            let uploadPath = "imports/fitness/apple-health/raw/\(pathComponents[0])/\(pathComponents[1])/\(pathComponents[2])/\(syncTimestamp).json"

            let dayDate = dayDateFormatter.date(from: dayString) ?? Date()

            batches.append(DaySamples(
                date: dayDate,
                collectorID: id,
                uploadPath: uploadPath,
                data: jsonData,
                anchorToken: sorted.last?.end ?? sorted.last?.start
            ))
        }

        return CollectionResult(batches: batches, stats: stats)
    }

    func commitAnchor(for batch: DaySamples) async {
        if let date = batch.anchorToken as? Date {
            saveAnchorDate(date)
        }
    }

    // MARK: - HealthKit Queries

    private func querySamples(type: HKSampleType, since startDate: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
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

    // MARK: - Sample Encoding

    /// Converts an HKSample to our raw JSON-friendly struct.
    private func encodeSample(_ sample: HKSample) -> RawHealthSample? {
        let type = sample.sampleType.identifier
        let source = sample.sourceRevision.source.bundleIdentifier
        let device = sample.sourceRevision.productType ?? sample.device?.name

        if let quantitySample = sample as? HKQuantitySample {
            let typeID = HKQuantityTypeIdentifier(rawValue: quantitySample.quantityType.identifier)
            let unit = preferredUnit(for: typeID)
            let value = quantitySample.quantity.doubleValue(for: unit)

            return RawHealthSample(
                type: type,
                start: quantitySample.startDate,
                end: quantitySample.endDate,
                value: value,
                unit: unit.unitString,
                source: source,
                device: device,
                metadata: encodeMetadata(sample.metadata)
            )
        }

        if let categorySample = sample as? HKCategorySample {
            return RawHealthSample(
                type: type,
                start: categorySample.startDate,
                end: categorySample.endDate,
                value: Double(categorySample.value),
                unit: nil,
                source: source,
                device: device,
                metadata: encodeMetadata(sample.metadata)
            )
        }

        if let workout = sample as? HKWorkout {
            var meta = encodeMetadata(workout.metadata) ?? [:]
            meta["workoutActivityType"] = workout.workoutActivityType.rawValue
            meta["duration"] = workout.duration
            if let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                meta["totalEnergyBurned"] = energy.doubleValue(for: .kilocalorie())
                meta["totalEnergyBurnedUnit"] = "kcal"
            }
            if let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() {
                meta["totalDistance"] = distance.doubleValue(for: .meter())
                meta["totalDistanceUnit"] = "m"
            }

            return RawHealthSample(
                type: type,
                start: workout.startDate,
                end: workout.endDate,
                value: nil,
                unit: nil,
                source: source,
                device: device,
                metadata: meta
            )
        }

        return nil
    }

    /// Converts HealthKit metadata dictionary to a JSON-safe dictionary.
    private func encodeMetadata(_ metadata: [String: Any]?) -> [String: Any]? {
        guard let metadata, !metadata.isEmpty else { return nil }

        var result: [String: Any] = [:]
        for (key, value) in metadata {
            // Only include JSON-compatible values
            if value is String || value is Int || value is Double || value is Bool {
                result[key] = value
            } else if let date = value as? Date {
                result[key] = ISO8601DateFormatter().string(from: date)
            } else if let quantity = value as? HKQuantity {
                // Try common units
                for unit in [HKUnit.count(), HKUnit.meter(), HKUnit.kilocalorie(), HKUnit.minute()] {
                    if quantity.is(compatibleWith: unit) {
                        result[key] = quantity.doubleValue(for: unit)
                        break
                    }
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Anchor Persistence

    private let anchorKey = "sync.anchor.healthkit"

    private func loadAnchorDate() -> Date? {
        UserDefaults.standard.object(forKey: anchorKey) as? Date
    }

    private func saveAnchorDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: anchorKey)
    }

    // MARK: - Helpers

    private func currentDeviceInfo() -> DeviceInfo {
        #if os(iOS)
        return DeviceInfo(
            name: UIDevice.current.name,
            model: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion
        )
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            name: Host.current().localizedName ?? "Mac",
            model: "Mac",
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
        #else
        return DeviceInfo(name: "Unknown", model: "Unknown", systemVersion: "Unknown")
        #endif
    }

    private let dayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}

// MARK: - Codable Types for JSON Output

/// The JSON payload written to each sync file.
private struct SyncFilePayload: Encodable {
    let syncedAt: Date
    let deviceInfo: DeviceInfo
    let samples: [RawHealthSample]

    enum CodingKeys: String, CodingKey {
        case syncedAt = "synced_at"
        case deviceInfo = "device_info"
        case samples
    }
}

/// Device information included in each sync file.
struct DeviceInfo: Encodable {
    let name: String
    let model: String
    let systemVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case systemVersion = "system_version"
    }
}

/// A single raw HealthKit sample, ready for JSON encoding.
/// Follows the schema defined in data-collect.md.
struct RawHealthSample: Encodable {
    let type: String
    let start: Date
    let end: Date
    let value: Double?
    let unit: String?
    let source: String
    let device: String?
    let metadata: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case type, start, end, value, unit, source, device, metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(device, forKey: .device)

        // Encode metadata as a JSON object
        if let metadata, !metadata.isEmpty {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            // Use a nested unkeyed approach via raw JSON
            try container.encode(AnyCodable(jsonObject), forKey: .metadata)
        }
    }
}

/// Helper for encoding arbitrary JSON-compatible values.
private struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
