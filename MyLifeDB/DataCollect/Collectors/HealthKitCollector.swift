//
//  HealthKitCollector.swift
//  MyLifeDB
//
//  Collects health data from HealthKit using anchored queries.
//  Samples are exported raw (no aggregation) and grouped by startDate day.
//

import Foundation
import HealthKit
import CoreLocation
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
        // Health & Body — core vitals
        "steps", "distance", "flights", "active_energy", "basal_energy", "exercise_min",
        "stand_hours", "heart_rate", "hrv", "blood_oxygen", "respiratory_rate",
        "vo2max", "body_weight", "body_height", "body_fat", "lean_body_mass", "bmi",
        "waist_circumference", "wrist_temperature", "walking_steadiness",
        // Cardiovascular events & metabolic
        "high_heart_rate_event", "low_heart_rate_event", "irregular_rhythm_event",
        "afib_burden", "blood_pressure", "blood_glucose",
        // Mobility metrics
        "walking_speed", "walking_step_length", "walking_asymmetry",
        "walking_double_support", "stair_ascent_speed", "stair_descent_speed",
        // Sleep
        "sleep_duration", "sleep_stages", "bedtime", "sleep_consistency",
        // Fitness
        "workouts", "running", "swimming", "cycling", "workout_routes",
        // Nutrition
        "water", "caffeine", "calories_in",
        // Audio & environment
        "noise", "headphone_audio", "uv_exposure",
        // Mindfulness
        "mindful_min", "mood",
    ]

    // MARK: - Private

    private let store = HKHealthStore()

    // MARK: - Enum-to-String Mappings
    //
    // DESIGN RULE: Store human-readable strings, never opaque numeric enums.
    // The exported JSON files must be self-explanatory — readable by any person
    // or AI agent without our application or Apple's SDK headers. Long-term
    // sustainability and openness matter more than saving a few bytes.
    //
    // When Apple adds new HealthKit enum cases, add them here. Unmapped values
    // fall back to "unknown_<rawValue>" so files remain parseable even before
    // we update these tables.

    /// HKWorkoutActivityType.rawValue → human-readable name
    let workoutActivityTypeNames: [UInt: String] = [
        1:    "americanFootball",
        2:    "archery",
        3:    "australianFootball",
        4:    "badminton",
        5:    "baseball",
        6:    "basketball",
        7:    "bowling",
        8:    "boxing",
        9:    "climbing",
        10:   "cricket",
        11:   "crossTraining",
        12:   "curling",
        13:   "cycling",
        14:   "dance",
        16:   "elliptical",
        17:   "equestrianSports",
        18:   "fencing",
        19:   "fishing",
        20:   "functionalStrengthTraining",
        21:   "golf",
        22:   "gymnastics",
        23:   "handball",
        24:   "hiking",
        25:   "hockey",
        26:   "hunting",
        27:   "lacrosse",
        28:   "martialArts",
        29:   "mindAndBody",
        31:   "paddleSports",
        32:   "play",
        33:   "preparationAndRecovery",
        34:   "racquetball",
        35:   "rowing",
        36:   "rugby",
        37:   "running",
        38:   "sailing",
        39:   "skatingSports",
        40:   "snowSports",
        41:   "soccer",
        42:   "softball",
        43:   "squash",
        44:   "stairClimbing",
        45:   "surfingSports",
        46:   "swimming",
        47:   "tableTennis",
        48:   "tennis",
        49:   "trackAndField",
        50:   "traditionalStrengthTraining",
        51:   "volleyball",
        52:   "walking",
        53:   "waterFitness",
        54:   "waterPolo",
        55:   "waterSports",
        56:   "wrestling",
        57:   "yoga",
        58:   "barre",
        59:   "coreTraining",
        60:   "crossCountrySkiing",
        61:   "downhillSkiing",
        62:   "flexibility",
        63:   "highIntensityIntervalTraining",
        64:   "jumpRope",
        65:   "kickboxing",
        66:   "pilates",
        67:   "snowboarding",
        68:   "stairs",
        69:   "stepTraining",
        70:   "wheelchairWalkPace",
        71:   "wheelchairRunPace",
        72:   "taiChi",
        73:   "mixedCardio",
        74:   "handCycling",
        75:   "discSports",
        76:   "fitnessGaming",
        77:   "cardioDance",
        78:   "socialDance",
        79:   "pickleball",
        80:   "cooldown",
        81:   "underwaterDiving",
        82:   "swimBikeRun",
        83:   "transition",
        3000: "other",
    ]

    /// HKCategoryValueSleepAnalysis.rawValue → human-readable name
    private let sleepAnalysisValueNames: [Int: String] = [
        0: "inBed",
        1: "asleepUnspecified",
        2: "awake",
        3: "asleepCore",
        4: "asleepDeep",
        5: "asleepREM",
    ]

    /// HKCategoryValueAppleStandHour.rawValue → human-readable name
    private let standHourValueNames: [Int: String] = [
        0: "idle",
        1: "stood",
    ]

    /// HKHeartRateMotionContext.rawValue → human-readable name
    /// HealthKit stores this under the metadata key "HKMetadataKeyHeartRateMotionContext".
    private let heartRateMotionContextNames: [Int: String] = [
        0: "notSet",
        1: "sedentary",
        2: "active",
    ]

    /// HKCategoryValuePresence.rawValue → human-readable name.
    /// Used for cardiac event types (highHeartRate, lowHeartRate, irregularRhythm).
    private let presenceValueNames: [Int: String] = [
        0: "notPresent",
        1: "present",
    ]

    /// Category value mappings keyed by HKCategoryType identifier.
    /// Used in encodeSample() to convert numeric category values to strings.
    private var categoryValueNames: [String: [Int: String]] {
        [
            HKCategoryType(.sleepAnalysis).identifier:          sleepAnalysisValueNames,
            HKCategoryType(.appleStandHour).identifier:         standHourValueNames,
            HKCategoryType(.highHeartRateEvent).identifier:     presenceValueNames,
            HKCategoryType(.lowHeartRateEvent).identifier:      presenceValueNames,
            HKCategoryType(.irregularHeartRhythmEvent).identifier: presenceValueNames,
        ]
    }

    /// Converts a workout activity type rawValue to a human-readable string.
    private func workoutActivityTypeName(for rawValue: UInt) -> String {
        workoutActivityTypeNames[rawValue] ?? "unknown_\(rawValue)"
    }

    /// Converts a category sample's numeric value to a human-readable string,
    /// based on the sample's type identifier. Returns a numeric fallback for
    /// unmapped types (e.g. mindfulSession, which has no meaningful value enum).
    private func categoryValueName(for value: Int, type: String) -> SampleValue {
        if let mapping = categoryValueNames[type] {
            return .category(mapping[value] ?? "unknown_\(value)")
        }
        // Types without a meaningful category enum (e.g. mindfulSession)
        // keep the numeric value as-is.
        return .numeric(Double(value))
    }

    /// How far back to look on first sync (no anchor yet)
    private let initialLookbackDays = 7

    // MARK: - Source ID → HKSampleType Mapping

    /// Returns the HealthKit sample types needed for a given source ID.
    /// One source ID may map to multiple HK types (e.g., "heart_rate" covers
    /// heartRate, restingHeartRate, walkingHeartRateAverage).
    private func hkTypes(for sourceID: String) -> [HKSampleType] {
        switch sourceID {
        // Health & Body — core vitals
        case "steps":             return [HKQuantityType(.stepCount)]
        case "distance":          return [HKQuantityType(.distanceWalkingRunning)]
        case "flights":           return [HKQuantityType(.flightsClimbed)]
        case "active_energy":     return [HKQuantityType(.activeEnergyBurned)]
        case "basal_energy":      return [HKQuantityType(.basalEnergyBurned)]
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
        case "body_height":       return [HKQuantityType(.height)]
        case "body_fat":          return [HKQuantityType(.bodyFatPercentage)]
        case "lean_body_mass":    return [HKQuantityType(.leanBodyMass)]
        case "bmi":               return [HKQuantityType(.bodyMassIndex)]
        case "waist_circumference": return [HKQuantityType(.waistCircumference)]
        case "wrist_temperature": return [HKQuantityType(.appleSleepingWristTemperature)]
        case "walking_steadiness": return [HKQuantityType(.appleWalkingSteadiness)]

        // Cardiovascular events & metabolic
        case "high_heart_rate_event":  return [HKCategoryType(.highHeartRateEvent)]
        case "low_heart_rate_event":   return [HKCategoryType(.lowHeartRateEvent)]
        case "irregular_rhythm_event": return [HKCategoryType(.irregularHeartRhythmEvent)]
        case "afib_burden":            return [HKQuantityType(.atrialFibrillationBurden)]
        case "blood_pressure":         return [HKQuantityType(.bloodPressureSystolic),
                                               HKQuantityType(.bloodPressureDiastolic)]
        case "blood_glucose":          return [HKQuantityType(.bloodGlucose)]

        // Mobility metrics (Apple Watch, iOS 14+)
        case "walking_speed":          return [HKQuantityType(.walkingSpeed)]
        case "walking_step_length":    return [HKQuantityType(.walkingStepLength)]
        case "walking_asymmetry":      return [HKQuantityType(.walkingAsymmetryPercentage)]
        case "walking_double_support": return [HKQuantityType(.walkingDoubleSupportPercentage)]
        case "stair_ascent_speed":     return [HKQuantityType(.stairAscentSpeed)]
        case "stair_descent_speed":    return [HKQuantityType(.stairDescentSpeed)]

        // Sleep — all map to the same HK type
        case "sleep_duration", "sleep_stages", "bedtime", "sleep_consistency":
            return [HKCategoryType(.sleepAnalysis)]

        // Fitness
        case "workouts", "swimming", "cycling":
            return [HKWorkoutType.workoutType()]
        case "workout_routes": return [HKSeriesType.workoutRoute()]
        case "running":
            // Workouts + running-specific biomechanics (Apple Watch, iOS 16+)
            return [
                HKWorkoutType.workoutType(),
                HKQuantityType(.runningStrideLength),
                HKQuantityType(.runningVerticalOscillation),
                HKQuantityType(.runningPower),
                HKQuantityType(.runningGroundContactTime),
                HKQuantityType(.runningSpeed),
            ]

        // Nutrition
        case "water":         return [HKQuantityType(.dietaryWater)]
        case "caffeine":      return [HKQuantityType(.dietaryCaffeine)]
        case "calories_in":   return [HKQuantityType(.dietaryEnergyConsumed)]

        // Audio & environment
        case "noise":           return [HKQuantityType(.environmentalAudioExposure)]
        case "headphone_audio": return [HKQuantityType(.headphoneAudioExposure)]
        case "uv_exposure":     return [HKQuantityType(.uvExposure)]

        // Mindfulness
        case "mindful_min":   return [HKCategoryType(.mindfulSession)]
        case "mood":          return [] // iOS 18+ HKStateOfMind — requires dedicated query

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
        // Activity & energy
        case .stepCount:                        return .count()
        case .distanceWalkingRunning:           return .meter()
        case .flightsClimbed:                   return .count()
        case .activeEnergyBurned:               return .kilocalorie()
        case .basalEnergyBurned:                return .kilocalorie()
        case .appleExerciseTime:                return .minute()
        case .appleStandTime:                   return .minute()
        // Heart
        case .heartRate:                        return .count().unitDivided(by: .minute())
        case .restingHeartRate:                 return .count().unitDivided(by: .minute())
        case .walkingHeartRateAverage:          return .count().unitDivided(by: .minute())
        case .heartRateRecoveryOneMinute:       return .count().unitDivided(by: .minute())
        case .heartRateVariabilitySDNN:         return .secondUnit(with: .milli)
        case .atrialFibrillationBurden:         return .percent()
        // Vitals
        case .oxygenSaturation:                 return .percent()
        case .respiratoryRate:                  return .count().unitDivided(by: .minute())
        case .vo2Max:                           return HKUnit(from: "ml/kg*min")
        case .bloodPressureSystolic:            return .millimeterOfMercury()
        case .bloodPressureDiastolic:           return .millimeterOfMercury()
        case .bloodGlucose:                     return HKUnit(from: "mg/dL")
        // Body measurements
        case .bodyMass:                         return .gramUnit(with: .kilo)
        case .height:                           return .meter()
        case .bodyFatPercentage:                return .percent()
        case .leanBodyMass:                     return .gramUnit(with: .kilo)
        case .bodyMassIndex:                    return .count()
        case .waistCircumference:               return .meter()
        case .appleSleepingWristTemperature:    return .degreeCelsius()
        case .appleWalkingSteadiness:           return .percent()
        // Mobility
        case .walkingSpeed:                     return .meter().unitDivided(by: .second())
        case .walkingStepLength:                return .meter()
        case .walkingAsymmetryPercentage:       return .percent()
        case .walkingDoubleSupportPercentage:   return .percent()
        case .stairAscentSpeed:                 return .meter().unitDivided(by: .second())
        case .stairDescentSpeed:                return .meter().unitDivided(by: .second())
        // Running biomechanics (Apple Watch, iOS 16+)
        case .runningStrideLength:              return .meter()
        case .runningVerticalOscillation:       return .meter()
        case .runningPower:                     return HKUnit(from: "W")
        case .runningGroundContactTime:         return .secondUnit(with: .milli)
        case .runningSpeed:                     return .meter().unitDivided(by: .second())
        // Nutrition
        case .dietaryWater:                     return .liter()
        case .dietaryCaffeine:                  return .gramUnit(with: .milli)
        case .dietaryEnergyConsumed:            return .kilocalorie()
        // Audio & environment
        case .environmentalAudioExposure:       return HKUnit(from: "dBASPL")
        case .headphoneAudioExposure:           return HKUnit(from: "dBASPL")
        case .uvExposure:                       return .count()
        default:                                return .count()
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

        var batches: [DaySamples] = []

        if !allRawSamples.isEmpty {
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

                // Path: imports/fitness/apple-health/YYYY/MM/DD/sample-<timestamp>.json
                let pathComponents = dayString.split(separator: "-")
                guard pathComponents.count == 3 else { continue }
                let uploadPath = "imports/fitness/apple-health/\(pathComponents[0])/\(pathComponents[1])/\(pathComponents[2])/sample-\(syncTimestamp).json"

                let dayDate = dayDateFormatter.date(from: dayString) ?? Date()

                batches.append(DaySamples(
                    date: dayDate,
                    collectorID: id,
                    uploadPath: uploadPath,
                    data: jsonData,
                    anchorToken: sorted.last?.end ?? sorted.last?.start
                ))
            }
        }

        // Also collect workouts (separate files, separate anchor)
        if !allHKTypes(for: enabled).filter({ $0 is HKWorkoutType }).isEmpty {
            let workoutStart = loadWorkoutAnchorDate()
                ?? Calendar.current.date(byAdding: .day, value: -initialLookbackDays, to: Date())!
            let workoutBatches = (try? await collectWorkouts(since: workoutStart)) ?? []
            batches.append(contentsOf: workoutBatches)
        }

        return CollectionResult(batches: batches, stats: stats)
    }

    func commitAnchor(for batch: DaySamples) async {
        if let date = batch.anchorToken as? Date {
            if batch.uploadPath.contains("/workout-") {
                saveWorkoutAnchorDate(date)
            } else {
                saveAnchorDate(date)
            }
        }
    }

    // MARK: - Workout Collection

    /// Queries workouts since `startDate`, fetches their GPS routes,
    /// and returns DaySamples with workout-<UUID>.json upload paths.
    func collectWorkouts(since startDate: Date) async throws -> [DaySamples] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate, end: Date(), options: .strictStartDate
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
        let calendar = Calendar.current

        for sample in workouts {
            guard let workout = sample as? HKWorkout else { continue }

            let uuid = workout.uuid.uuidString
            let activityType = workoutActivityTypeName(for: workout.workoutActivityType.rawValue)

            // Build stats dict
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

            // Fetch GPS route (nil for indoor workouts)
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

            // Path: imports/fitness/apple-health/YYYY/MM/DD/workout-<UUID>.json
            let components = calendar.dateComponents([.year, .month, .day], from: workout.startDate)
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

    /// Fetches all CLLocation points for a workout's GPS route.
    /// Returns nil if the workout has no associated route (indoor workouts).
    private func fetchRoute(for workout: HKWorkout) async throws -> [RoutePoint]? {
        let routePredicate = HKQuery.predicateForObjects(from: workout)

        // First: find the HKWorkoutRoute associated with this workout
        let routes = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKSample], Error>) in
            let q = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: routePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: results ?? []) }
            }
            store.execute(q)
        }

        guard let route = routes.first as? HKWorkoutRoute else { return nil }

        // Second: stream all CLLocation points from the route
        var points: [RoutePoint] = []

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let q = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    if !resumed { resumed = true; cont.resume(throwing: error) }
                    return
                }
                if let locations {
                    points.append(contentsOf: locations.map { loc in
                        RoutePoint(
                            timestamp: loc.timestamp,
                            lat: loc.coordinate.latitude,
                            lon: loc.coordinate.longitude,
                            alt: loc.altitude,
                            hAcc: loc.horizontalAccuracy,
                            vAcc: loc.verticalAccuracy,
                            speed: loc.speed,
                            speedAcc: loc.speedAccuracy,
                            course: loc.course,
                            courseAcc: loc.courseAccuracy
                        )
                    })
                }
                if done, !resumed { resumed = true; cont.resume() }
            }
            store.execute(q)
        }

        return points.isEmpty ? nil : points
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
                value: .numeric(value),
                unit: unit.unitString,
                source: source,
                device: device,
                metadata: encodeMetadata(sample.metadata)
            )
        }

        if let categorySample = sample as? HKCategorySample {
            // Convert numeric category value to a human-readable string
            // (e.g. sleep stage 4 → "asleepDeep", stand hour 1 → "stood").
            // See categoryValueNames mapping and the design rule comment above.
            let resolved = categoryValueName(for: categorySample.value, type: type)

            return RawHealthSample(
                type: type,
                start: categorySample.startDate,
                end: categorySample.endDate,
                value: resolved,
                unit: nil,
                source: source,
                device: device,
                metadata: encodeMetadata(sample.metadata)
            )
        }

        // Workouts are exported as standalone workout-<UUID>.json files,
        // not as entries in the sample batch.
        if sample is HKWorkout {
            return nil
        }

        return nil
    }

    /// Metadata keys whose integer values should be converted to human-readable
    /// strings. Add new entries here when HealthKit introduces more enum-valued
    /// metadata. See the design rule comment at the top of this section.
    private let metadataEnumKeys: [String: [Int: String]] = [
        HKMetadataKeyHeartRateMotionContext: [
            0: "notSet",
            1: "sedentary",
            2: "active",
        ],
    ]

    /// Converts HealthKit metadata dictionary to a JSON-safe dictionary.
    /// Integer-valued enum metadata (e.g. heart rate motion context) is
    /// converted to human-readable strings — see design rule comment above.
    private func encodeMetadata(_ metadata: [String: Any]?) -> [String: Any]? {
        guard let metadata, !metadata.isEmpty else { return nil }

        var result: [String: Any] = [:]
        for (key, value) in metadata {
            // Convert known enum metadata from integers to strings
            if let mapping = metadataEnumKeys[key], let intValue = value as? Int {
                result[key] = mapping[intValue] ?? "unknown_\(intValue)"
            } else if value is String || value is Int || value is Double || value is Bool {
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

    // MARK: - Workout Anchor Persistence

    private let workoutAnchorKey = "sync.anchor.healthkit.workouts"

    private func loadWorkoutAnchorDate() -> Date? {
        UserDefaults.standard.object(forKey: workoutAnchorKey) as? Date
    }

    private func saveWorkoutAnchorDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: workoutAnchorKey)
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

/// The `value` field of a health sample. Encodes as a JSON number for
/// quantity types (heart rate, steps, etc.) and a JSON string for category
/// types (sleep stages, stand hours, etc.).
///
/// This keeps the data self-describing: `"value": "asleepDeep"` is
/// immediately meaningful, unlike the HealthKit raw integer `4`.
enum SampleValue: Encodable {
    case numeric(Double)
    case category(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .numeric(let v):  try container.encode(v)
        case .category(let s): try container.encode(s)
        }
    }
}

/// A single raw HealthKit sample, ready for JSON encoding.
/// Follows the schema defined in data-collect.md.
struct RawHealthSample: Encodable {
    let type: String
    let start: Date
    let end: Date
    let value: SampleValue?
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
struct AnyCodable: Encodable {
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
