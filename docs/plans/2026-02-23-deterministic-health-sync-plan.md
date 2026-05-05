# Deterministic Health Sync — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace timestamp-based, all-types-in-one-file health sync with deterministic per-type-per-day files, local watermarking, and a Sync All button.

**Architecture:** One file per HK type per calendar day at a deterministic path (`YYYY/MM/DD/<type-kebab>.json`). Each sync rebuilds complete day snapshots from midnight. SHA-256 watermarks skip unchanged uploads. "Sync All" queries all HealthKit history for a full re-sync.

**Tech Stack:** Swift, SwiftUI, HealthKit, CryptoKit (SHA-256), `@Observable`, `@AppStorage`

**Design doc:** `docs/plans/2026-02-23-deterministic-health-sync-design.md`

---

### Task 1: HK Type Identifier → Kebab-Case Filename

Add a pure function that converts HealthKit type identifiers to deterministic filenames. This is the foundation — every other task depends on it.

**Files:**
- Create: `MyLifeDB/DataCollect/Collectors/HKTypeFileName.swift`
- Create: `MyLifeDBTests/HKTypeFileNameTests.swift`

**Step 1: Write the failing tests**

```swift
// MyLifeDBTests/HKTypeFileNameTests.swift
import Testing
@testable import MyLifeDB

struct HKTypeFileNameTests {

    // MARK: - Quantity types: strip prefix, kebab-case

    @Test func quantityTypeStepCount() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierStepCount")
        #expect(name == "step-count")
    }

    @Test func quantityTypeHeartRate() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierHeartRate")
        #expect(name == "heart-rate")
    }

    @Test func quantityTypeHeartRateVariabilitySDNN() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        #expect(name == "heart-rate-variability-sdnn")
    }

    @Test func quantityTypeVO2Max() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierVO2Max")
        #expect(name == "vo2-max")
    }

    @Test func quantityTypeAppleExerciseTime() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierAppleExerciseTime")
        #expect(name == "apple-exercise-time")
    }

    @Test func quantityTypeBloodPressureSystolic() {
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierBloodPressureSystolic")
        #expect(name == "blood-pressure-systolic")
    }

    // MARK: - Category types: strip prefix, kebab-case

    @Test func categoryTypeSleepAnalysis() {
        let name = HKTypeFileName.fileName(for: "HKCategoryTypeIdentifierSleepAnalysis")
        #expect(name == "sleep-analysis")
    }

    @Test func categoryTypeMindfulSession() {
        let name = HKTypeFileName.fileName(for: "HKCategoryTypeIdentifierMindfulSession")
        #expect(name == "mindful-session")
    }

    @Test func categoryTypeAppleStandHour() {
        let name = HKTypeFileName.fileName(for: "HKCategoryTypeIdentifierAppleStandHour")
        #expect(name == "apple-stand-hour")
    }

    // MARK: - Workout type: uses "workout" prefix

    @Test func workoutTypeNoActivity() {
        // Base workout type without activity → just "workout"
        let name = HKTypeFileName.fileName(for: "HKWorkoutTypeIdentifier")
        #expect(name == "workout")
    }

    @Test func workoutWithActivityType() {
        let name = HKTypeFileName.workoutFileName(activityName: "running")
        #expect(name == "workout-running")
    }

    @Test func workoutWithFunctionalStrengthTraining() {
        let name = HKTypeFileName.workoutFileName(activityName: "functionalStrengthTraining")
        #expect(name == "workout-functional-strength-training")
    }

    // MARK: - Edge cases

    @Test func unknownTypePassesThrough() {
        let name = HKTypeFileName.fileName(for: "HKSomeFutureTypeIdentifierNewThing")
        // Should still strip known prefixes and kebab-case
        #expect(name == "new-thing")
    }

    @Test func consecutiveUppercase() {
        // "SDNN" should become "sdnn", "VO2" should become "vo2"
        let name = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        #expect(name == "heart-rate-variability-sdnn")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/HKTypeFileNameTests 2>&1 | tail -20`
Expected: Compilation error — `HKTypeFileName` not defined.

**Step 3: Write the implementation**

```swift
// MyLifeDB/DataCollect/Collectors/HKTypeFileName.swift
//
//  HKTypeFileName.swift
//  MyLifeDB
//
//  Converts HealthKit type identifiers to deterministic kebab-case filenames.
//  e.g. "HKQuantityTypeIdentifierStepCount" → "step-count"
//       Workout + "running" → "workout-running"
//

import Foundation

enum HKTypeFileName {

    /// Known prefixes to strip from HK type identifiers.
    private static let prefixes = [
        "HKQuantityTypeIdentifier",
        "HKCategoryTypeIdentifier",
        "HKWorkoutTypeIdentifier",
        "HKCorrelationTypeIdentifier",
        "HKDataTypeIdentifier",
    ]

    /// Convert an HK type identifier to a kebab-case filename (without extension).
    ///
    ///     HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierStepCount")
    ///     // → "step-count"
    static func fileName(for hkIdentifier: String) -> String {
        var name = hkIdentifier
        for prefix in prefixes {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }
        // "HKWorkoutTypeIdentifier" with nothing after → "workout"
        if name.isEmpty { return "workout" }
        return camelToKebab(name)
    }

    /// Filename for a workout with a specific activity type.
    ///
    ///     HKTypeFileName.workoutFileName(activityName: "running")
    ///     // → "workout-running"
    static func workoutFileName(activityName: String) -> String {
        "workout-\(camelToKebab(activityName))"
    }

    /// Convert camelCase/PascalCase to kebab-case.
    /// Handles consecutive uppercase (e.g. "SDNN" → "sdnn", "VO2Max" → "vo2-max").
    private static func camelToKebab(_ input: String) -> String {
        var result = ""
        let chars = Array(input)

        for i in chars.indices {
            let c = chars[i]
            if c.isUppercase {
                let prevIsLower = i > 0 && chars[i - 1].isLowercase
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                let prevIsDigit = i > 0 && chars[i - 1].isNumber

                // Insert hyphen before:
                // - an uppercase after a lowercase (stepCount → step-Count)
                // - an uppercase followed by lowercase in a run of uppers (SDNNHeart → SDNN-Heart)
                // - an uppercase after a digit (VO2Max → VO2-Max)
                if !result.isEmpty && (prevIsLower || prevIsDigit || (nextIsLower && i > 0 && chars[i - 1].isUppercase)) {
                    result.append("-")
                }
                result.append(c.lowercased())
            } else {
                result.append(c)
            }
        }
        return result
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/HKTypeFileNameTests 2>&1 | tail -20`
Expected: All tests PASS. If any edge cases fail, adjust `camelToKebab` logic and re-run.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/HKTypeFileName.swift MyLifeDBTests/HKTypeFileNameTests.swift
git commit -m "feat(sync): add HK type identifier to kebab-case filename mapping"
```

---

### Task 2: New Per-Type Payload Format (TypeDayPayload)

Replace `SyncFilePayload` (all types mixed, includes `syncedAt` + `deviceInfo`) with `TypeDayPayload` (one type per file, data-only, deterministic).

**Files:**
- Create: `MyLifeDB/DataCollect/Collectors/TypeDayPayload.swift`
- Create: `MyLifeDBTests/TypeDayPayloadTests.swift`

**Step 1: Write the failing tests**

```swift
// MyLifeDBTests/TypeDayPayloadTests.swift
import Testing
import Foundation
@testable import MyLifeDB

struct TypeDayPayloadTests {

    // MARK: - Basic encoding

    @Test func encodesQuantityTypePayload() throws {
        let sample = RawHealthSample(
            type: "HKQuantityTypeIdentifierStepCount",
            start: makeDate(2026, 2, 9, 10, 0, 0, tz: "Asia/Singapore"),
            end: makeDate(2026, 2, 9, 10, 15, 0, tz: "Asia/Singapore"),
            value: .numeric(250),
            unit: "count",
            source: "com.apple.health",
            device: "iPhone 15 Pro",
            metadata: nil
        )

        let payload = TypeDayPayload(
            type: "HKQuantityTypeIdentifierStepCount",
            date: "2026-02-09",
            timezone: "Asia/Singapore",
            unit: "count",
            samples: [sample]
        )

        let data = try TypeDayPayload.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "HKQuantityTypeIdentifierStepCount")
        #expect(json["date"] as? String == "2026-02-09")
        #expect(json["timezone"] as? String == "Asia/Singapore")
        #expect(json["unit"] as? String == "count")
        #expect((json["samples"] as? [[String: Any]])?.count == 1)
    }

    @Test func encodesWorkoutPayloadWithoutUnit() throws {
        let sample = RawHealthSample(
            type: "HKWorkoutTypeIdentifier",
            start: makeDate(2026, 2, 9, 7, 30, 0, tz: "Asia/Singapore"),
            end: makeDate(2026, 2, 9, 8, 0, 0, tz: "Asia/Singapore"),
            value: nil,
            unit: nil,
            source: "com.apple.health",
            device: "Apple Watch",
            metadata: ["workoutActivityType": "running", "duration": 1800.0]
        )

        let payload = TypeDayPayload(
            type: "HKWorkoutTypeIdentifier",
            date: "2026-02-09",
            timezone: "Asia/Singapore",
            unit: nil,
            samples: [sample]
        )

        let data = try TypeDayPayload.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // unit should be absent (nil), not "null" string
        #expect(json["unit"] == nil || json["unit"] is NSNull)
    }

    // MARK: - Determinism: same input → same bytes

    @Test func deterministicEncoding() throws {
        let samples = [
            makeSample(start: (10, 0), end: (10, 15), value: 100, source: "com.apple.a"),
            makeSample(start: (10, 0), end: (10, 15), value: 200, source: "com.apple.b"),
            makeSample(start: (9, 30), end: (9, 45), value: 50, source: "com.apple.a"),
        ]

        let payload = TypeDayPayload(
            type: "HKQuantityTypeIdentifierStepCount",
            date: "2026-02-09",
            timezone: "Asia/Singapore",
            unit: "count",
            samples: samples
        )

        let data1 = try TypeDayPayload.encode(payload)
        let data2 = try TypeDayPayload.encode(payload)

        #expect(data1 == data2, "Same payload must produce identical bytes")
    }

    @Test func samplesSortedByStartEndSource() throws {
        // Deliberately unsorted input
        let s1 = makeSample(start: (10, 0), end: (10, 15), value: 100, source: "com.b")
        let s2 = makeSample(start: (9, 0), end: (9, 15), value: 50, source: "com.a")
        let s3 = makeSample(start: (10, 0), end: (10, 15), value: 200, source: "com.a")

        let payload = TypeDayPayload(
            type: "HKQuantityTypeIdentifierStepCount",
            date: "2026-02-09",
            timezone: "Asia/Singapore",
            unit: "count",
            samples: [s1, s2, s3]
        )

        let data = try TypeDayPayload.encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodedSamples = json["samples"] as! [[String: Any]]

        // s2 (9:00, com.a) < s3 (10:00, com.a) < s1 (10:00, com.b)
        #expect(encodedSamples[0]["source"] as? String == "com.a")
        #expect(encodedSamples[1]["source"] as? String == "com.a")
        #expect(encodedSamples[2]["source"] as? String == "com.b")
    }

    // MARK: - Helpers

    private func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int, tz: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private func makeSample(start: (Int, Int), end: (Int, Int), value: Double, source: String) -> RawHealthSample {
        RawHealthSample(
            type: "HKQuantityTypeIdentifierStepCount",
            start: makeDate(2026, 2, 9, start.0, start.1, 0, tz: "Asia/Singapore"),
            end: makeDate(2026, 2, 9, end.0, end.1, 0, tz: "Asia/Singapore"),
            value: .numeric(value),
            unit: "count",
            source: source,
            device: nil,
            metadata: nil
        )
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/TypeDayPayloadTests 2>&1 | tail -20`
Expected: Compilation error — `TypeDayPayload` not defined.

**Step 3: Write the implementation**

```swift
// MyLifeDB/DataCollect/Collectors/TypeDayPayload.swift
//
//  TypeDayPayload.swift
//  MyLifeDB
//
//  The JSON payload for a single HK type on a single calendar day.
//  Deterministic: same samples → same bytes → same SHA-256 hash.
//

import Foundation

/// One file's worth of health data: all samples of one HK type for one day.
struct TypeDayPayload: Encodable {
    let type: String        // Full HK type identifier
    let date: String        // "YYYY-MM-DD"
    let timezone: String    // IANA timezone (e.g. "Asia/Singapore")
    let unit: String?       // Quantity unit, nil for category/workout types
    let samples: [RawHealthSample]

    enum CodingKeys: String, CodingKey {
        case type, date, timezone, unit, samples
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(date, forKey: .date)
        try container.encode(timezone, forKey: .timezone)
        try container.encodeIfPresent(unit, forKey: .unit)

        // Sort samples deterministically: (start, end, source)
        let sorted = samples.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
            return a.source < b.source
        }
        try container.encode(sorted, forKey: .samples)
    }

    /// Encode to deterministic JSON bytes (sorted keys, consistent formatting).
    static func encode(_ payload: TypeDayPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            // ISO8601 with timezone offset — deterministic format
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(payload)
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/TypeDayPayloadTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/TypeDayPayload.swift MyLifeDBTests/TypeDayPayloadTests.swift
git commit -m "feat(sync): add TypeDayPayload for deterministic per-type-per-day JSON"
```

---

### Task 3: Watermark Manager

Add a simple hash-based watermark system: compute SHA-256 of file data, compare with last uploaded hash, skip if unchanged.

**Files:**
- Create: `MyLifeDB/DataCollect/SyncWatermark.swift`
- Create: `MyLifeDBTests/SyncWatermarkTests.swift`

**Step 1: Write the failing tests**

```swift
// MyLifeDBTests/SyncWatermarkTests.swift
import Testing
import Foundation
@testable import MyLifeDB

struct SyncWatermarkTests {

    @Test func newFileHasNoWatermark() {
        let wm = SyncWatermark(store: MockDefaults())
        #expect(wm.hasChanged(path: "2026/02/09/step-count.json", data: Data("hello".utf8)))
    }

    @Test func unchangedFileIsSkipped() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)
        let data = Data("same content".utf8)

        #expect(wm.hasChanged(path: "a.json", data: data))
        wm.recordUpload(path: "a.json", data: data)
        #expect(!wm.hasChanged(path: "a.json", data: data))
    }

    @Test func changedFileIsDetected() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)

        let data1 = Data("v1".utf8)
        let data2 = Data("v2".utf8)

        wm.recordUpload(path: "a.json", data: data1)
        #expect(wm.hasChanged(path: "a.json", data: data2))
    }

    @Test func clearRemovesAll() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)

        wm.recordUpload(path: "a.json", data: Data("x".utf8))
        wm.clearAll()
        #expect(wm.hasChanged(path: "a.json", data: Data("x".utf8)))
    }

    @Test func differentPathsAreIndependent() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)
        let data = Data("same".utf8)

        wm.recordUpload(path: "a.json", data: data)
        #expect(wm.hasChanged(path: "b.json", data: data), "Different path should not match")
    }
}

/// In-memory mock for UserDefaults
final class MockDefaults: SyncWatermarkStore {
    private var dict: [String: String] = [:]

    func string(forKey key: String) -> String? { dict[key] }
    func set(_ value: String?, forKey key: String) {
        if let value { dict[key] = value } else { dict[key] = nil }
    }
    func removeAll(prefix: String) {
        dict = dict.filter { !$0.key.hasPrefix(prefix) }
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error — `SyncWatermark`, `SyncWatermarkStore` not defined.

**Step 3: Write the implementation**

```swift
// MyLifeDB/DataCollect/SyncWatermark.swift
//
//  SyncWatermark.swift
//  MyLifeDB
//
//  SHA-256 watermark to skip uploading unchanged files.
//

import Foundation
import CryptoKit

/// Protocol so we can inject MockDefaults in tests.
protocol SyncWatermarkStore {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func removeAll(prefix: String)
}

/// UserDefaults conformance.
extension UserDefaults: SyncWatermarkStore {
    func removeAll(prefix: String) {
        for key in dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            removeObject(forKey: key)
        }
    }
}

/// Tracks SHA-256 hashes of uploaded files to skip re-uploads.
final class SyncWatermark {
    private let store: SyncWatermarkStore
    private static let keyPrefix = "sync.watermark."

    init(store: SyncWatermarkStore = UserDefaults.standard) {
        self.store = store
    }

    /// Returns true if the data differs from the last recorded upload for this path.
    func hasChanged(path: String, data: Data) -> Bool {
        let newHash = sha256(data)
        let oldHash = store.string(forKey: Self.keyPrefix + path)
        return newHash != oldHash
    }

    /// Record that we successfully uploaded this data for this path.
    func recordUpload(path: String, data: Data) {
        store.set(sha256(data), forKey: Self.keyPrefix + path)
    }

    /// Clear all watermarks (used before Sync All if desired).
    func clearAll() {
        store.removeAll(prefix: Self.keyPrefix)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MyLifeDBTests/SyncWatermarkTests 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/SyncWatermark.swift MyLifeDBTests/SyncWatermarkTests.swift
git commit -m "feat(sync): add SHA-256 watermark manager for upload dedup"
```

---

### Task 4: Timezone-Aware Day Bucketing

Add a helper that extracts the calendar day string from a sample's start date, using the sample's timezone from HealthKit metadata.

**Files:**
- Create: `MyLifeDB/DataCollect/Collectors/SampleDayBucket.swift`
- Create: `MyLifeDBTests/SampleDayBucketTests.swift`

**Step 1: Write the failing tests**

```swift
// MyLifeDBTests/SampleDayBucketTests.swift
import Testing
import Foundation
@testable import MyLifeDB

struct SampleDayBucketTests {

    @Test func usesMetadataTimezone() {
        // Feb 9 23:30 UTC = Feb 10 07:30 in Asia/Singapore
        let utcDate = makeUTCDate(2026, 2, 9, 23, 30)
        let result = SampleDayBucket.dayKey(
            sampleStart: utcDate,
            metadata: ["HKTimeZone": "Asia/Singapore"]
        )
        #expect(result.date == "2026-02-10")
        #expect(result.timezone == "Asia/Singapore")
    }

    @Test func fallsBackToDeviceTimezone() {
        let utcDate = makeUTCDate(2026, 2, 9, 12, 0)
        let result = SampleDayBucket.dayKey(
            sampleStart: utcDate,
            metadata: nil
        )
        // Should use device's current timezone
        let expected = SampleDayBucket.formatDate(utcDate, in: TimeZone.current)
        #expect(result.date == expected)
        #expect(result.timezone == TimeZone.current.identifier)
    }

    @Test func invalidTimezoneInMetadataFallsBack() {
        let utcDate = makeUTCDate(2026, 2, 9, 12, 0)
        let result = SampleDayBucket.dayKey(
            sampleStart: utcDate,
            metadata: ["HKTimeZone": "Invalid/Zone"]
        )
        #expect(result.timezone == TimeZone.current.identifier)
    }

    @Test func midnightBoundaryCorrect() {
        // Exactly midnight in Tokyo (UTC+9) = Feb 8 15:00 UTC
        let utcDate = makeUTCDate(2026, 2, 8, 15, 0)
        let result = SampleDayBucket.dayKey(
            sampleStart: utcDate,
            metadata: ["HKTimeZone": "Asia/Tokyo"]
        )
        #expect(result.date == "2026-02-09")
    }

    private func makeUTCDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
```

**Step 2: Run tests to verify they fail**

Expected: Compilation error.

**Step 3: Write the implementation**

```swift
// MyLifeDB/DataCollect/Collectors/SampleDayBucket.swift
//
//  SampleDayBucket.swift
//  MyLifeDB
//
//  Determines which calendar day a sample belongs to,
//  using the sample's own timezone from HealthKit metadata.
//

import Foundation

enum SampleDayBucket {

    struct DayKey: Hashable {
        let date: String      // "YYYY-MM-DD"
        let timezone: String  // IANA identifier
    }

    /// Determine the calendar day for a sample, using its timezone.
    /// Falls back to device timezone if metadata is missing or invalid.
    static func dayKey(sampleStart: Date, metadata: [String: Any]?) -> DayKey {
        let tz: TimeZone
        if let tzName = metadata?["HKTimeZone"] as? String,
           let metaTZ = TimeZone(identifier: tzName) {
            tz = metaTZ
        } else {
            tz = TimeZone.current
        }

        return DayKey(
            date: formatDate(sampleStart, in: tz),
            timezone: tz.identifier
        )
    }

    /// Format a date as "YYYY-MM-DD" in a given timezone.
    static func formatDate(_ date: Date, in tz: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
```

**Step 4: Run tests to verify they pass**

Expected: All tests PASS.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/SampleDayBucket.swift MyLifeDBTests/SampleDayBucketTests.swift
git commit -m "feat(sync): add timezone-aware day bucketing for samples"
```

---

### Task 5: Rewrite `collectNewSamples()` — New Grouping + Full Day Queries

This is the core change. Rewrite the collection logic in `HealthKitCollector` to:
1. Query from `anchor.startOfDay` (not exact anchor time)
2. Group by `(day, HK type)` instead of just day
3. Build `TypeDayPayload` per group
4. Support full sync mode (query all history)

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift` (lines 352-451 — `collectNewSamples`, `commitAnchor`)
- Modify: `MyLifeDB/DataCollect/DataCollector.swift` (line 43 — add `fullSync` parameter)
- Modify: `MyLifeDB/DataCollect/CollectorTypes.swift` (update `DaySamples` comment)

**Step 1: Update `DataCollector` protocol to support full sync**

In `DataCollector.swift`, change the `collectNewSamples` signature:

```swift
// DataCollector.swift line 43 — add fullSync parameter
    /// Collect samples, grouped by day and type.
    /// When fullSync is true, queries all available history instead of from anchor.
    func collectNewSamples(fullSync: Bool) async throws -> CollectionResult
```

And update the `commitAnchor` comment in `DataCollector.swift` to match.

**Step 2: Rewrite `collectNewSamples` in HealthKitCollector**

Replace lines 352-451 of `HealthKitCollector.swift`:

```swift
    // MARK: - Data Collection

    func collectNewSamples(fullSync: Bool = false) async throws -> CollectionResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CollectorError.frameworkUnavailable("HealthKit is not available on this device")
        }

        let enabled = enabledSourceIDs
        guard !enabled.isEmpty else {
            throw CollectorError.noEnabledSources
        }

        let typesToQuery = allHKTypes(for: enabled)

        // Determine start date:
        // - fullSync: query all available history (nil start = beginning of time)
        // - incremental: from anchor's start-of-day (catches late-arriving data)
        let startDate: Date
        if fullSync {
            // HealthKit has data going back years — nil start gets everything,
            // but HKSampleQuery needs a date. Use a far-past date.
            startDate = Calendar.current.date(byAdding: .year, value: -50, to: Date())!
        } else {
            let anchor = loadAnchorDate()
                ?? Calendar.current.date(byAdding: .day, value: -initialLookbackDays, to: Date())!
            startDate = Calendar.current.startOfDay(for: anchor)
        }

        // Query each type and collect raw samples
        var allRawSamples: [RawHealthSample] = []
        var typesWithData = 0

        for type in typesToQuery {
            do {
                let samples = try await querySamples(type: type, since: startDate)
                let rawSamples = samples.compactMap { encodeSample($0) }
                if !rawSamples.isEmpty {
                    typesWithData += 1
                }
                allRawSamples.append(contentsOf: rawSamples)
            } catch {
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

        // Group by (day, HK type) — using sample's own timezone for day boundary
        typealias GroupKey = String  // "YYYY-MM-DD/<type-kebab>" or "YYYY-MM-DD/workout-<activity>"
        var grouped: [GroupKey: (dayKey: SampleDayBucket.DayKey, type: String, unit: String?, samples: [RawHealthSample])] = [:]

        for sample in allRawSamples {
            let dayKey = SampleDayBucket.dayKey(sampleStart: sample.start, metadata: sample.metadataRaw)

            // Determine the filename component
            let fileBase: String
            if sample.type == "HKWorkoutTypeIdentifier",
               let activityName = sample.metadata?["workoutActivityType"] as? String {
                // Split workouts by activity type
                fileBase = HKTypeFileName.workoutFileName(activityName: activityName)
            } else {
                fileBase = HKTypeFileName.fileName(for: sample.type)
            }

            let key = "\(dayKey.date)/\(fileBase)"

            if grouped[key] == nil {
                grouped[key] = (dayKey: dayKey, type: sample.type, unit: sample.unit, samples: [])
            }
            grouped[key]!.samples.append(sample)
        }

        // Build TypeDayPayload for each group → DaySamples batch
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

            // Path: imports/fitness/apple-health/YYYY/MM/DD/<type-kebab>.json
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
                anchorToken: group.samples.compactMap(\.end).max() ?? group.samples.compactMap(\.start).max()
            ))
        }

        return CollectionResult(batches: batches, stats: stats)
    }
```

**Step 3: Add `metadataRaw` accessor to `RawHealthSample`**

The `RawHealthSample.metadata` field is `[String: Any]?`, but we need it accessible as raw dict for timezone extraction. It's already there — just make sure it's accessible. In `HealthKitCollector.swift`, add a computed property alias if needed:

```swift
// In RawHealthSample struct (around line 681), add:
    /// Raw metadata dictionary (same as metadata, used for timezone extraction before encoding)
    var metadataRaw: [String: Any]? { metadata }
```

**Step 4: Remove the old `SyncFilePayload` struct**

Delete lines 635-645 of `HealthKitCollector.swift` (the `SyncFilePayload` struct). Also remove `DeviceInfo` struct (lines 648-658) if no longer used elsewhere — check first.

**Step 5: Remove `"raw/"` from the upload path**

The old path was `imports/fitness/apple-health/raw/YYYY/...`. The new path drops the `raw/` segment: `imports/fitness/apple-health/YYYY/...`. Check the design doc to confirm.

**Step 6: Build and test**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: Build succeeds. Run existing tests to make sure nothing broke.

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`

**Step 7: Commit**

```bash
git add -A
git commit -m "feat(sync): rewrite collectNewSamples for per-type-per-day deterministic files

- Group samples by (calendar day, HK type) instead of just day
- Use sample's timezone for day boundary (HKTimeZone metadata)
- Build TypeDayPayload per group (one file per type per day)
- Support fullSync parameter for Sync All
- Query from anchor's start-of-day to catch late-arriving data
- Remove old SyncFilePayload (all-types-mixed format)"
```

---

### Task 6: Wire Up Watermark in SyncManager

Integrate the watermark into the upload loop so unchanged files are skipped.

**Files:**
- Modify: `MyLifeDB/DataCollect/SyncManager.swift` (lines 154-293 — `performSync`)
- Modify: `MyLifeDB/DataCollect/SyncState.swift` (add `skipped` count to `SyncDetail`)

**Step 1: Add `filesSkipped` to SyncDetail**

In `SyncState.swift`, add to the `SyncDetail` struct (after line 60):

```swift
    /// Number of files skipped (unchanged per watermark)
    let filesSkipped: Int
```

**Step 2: Add watermark instance to SyncManager**

In `SyncManager.swift`, add to the private properties section (around line 50):

```swift
    @ObservationIgnored
    private let watermark = SyncWatermark()
```

**Step 3: Update `performSync` to use watermark**

In the upload loop (lines 219-244), wrap the upload call with a watermark check:

```swift
                // 2. Upload each day's batch (skip unchanged via watermark)
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
                        collectorFailures += 1
                        failures["\(collector.id)/\(batch.uploadPath)"] = error.localizedDescription
                    }
                }
```

Add `var skippedCount = 0` alongside `uploadedCount` at line 159, and pass it to `SyncDetail`:

```swift
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
```

**Step 4: Build and test**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`

Fix any compilation errors from the `SyncDetail` change (DataCollectView references `detail.filesUploaded` etc — make sure the view compiles).

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(sync): integrate watermark to skip unchanged file uploads"
```

---

### Task 7: Add Sync All Support to SyncManager + UI

Add the "Sync All" button and wire it through SyncManager to HealthKitCollector.

**Files:**
- Modify: `MyLifeDB/DataCollect/SyncManager.swift` (add `syncAll()` method)
- Modify: `MyLifeDB/DataCollect/SyncState.swift` (add `syncingAll` state)
- Modify: `MyLifeDB/Views/Me/DataCollectView.swift` (add Sync All button + skipped count display)

**Step 1: Add `syncingAll` state**

In `SyncState.swift`, update the `SyncState` enum:

```swift
enum SyncState: Equatable {
    case idle
    case syncing
    case syncingAll  // Full history sync in progress
}
```

**Step 2: Add `syncAll()` method to SyncManager**

In `SyncManager.swift`, add a public method (after `sync(force:)`):

```swift
    /// Trigger a full sync of all HealthKit history.
    /// Runs in background — does not block incremental syncs after completion.
    @MainActor
    func syncAll() {
        guard state == .idle else { return }
        guard AuthManager.shared.isAuthenticated else { return }

        syncTask?.cancel()
        syncTask = Task {
            await performSync(fullSync: true)
        }
    }
```

**Step 3: Update `performSync` to accept `fullSync` parameter**

Change the signature and pass it through:

```swift
    @MainActor
    private func performSync(fullSync: Bool = false) async {
        state = fullSync ? .syncingAll : .syncing
        // ... rest of method ...

        // In the collector loop, pass fullSync to collectNewSamples:
        let result = try await collector.collectNewSamples(fullSync: fullSync)
```

**Step 4: Update DataCollectView with Sync All button and skipped count**

In `DataCollectView.swift`, update the sync section (around lines 309-357) to add the Sync All button and show skipped files:

```swift
            // Sync status section
            Section {
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

                // Sync All button
                Button {
                    syncManager.syncAll()
                } label: {
                    Label("Sync All History", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(syncManager.state != .idle)

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

**Step 5: Update `syncDetailView` to show skipped count**

In the `syncDetailView` method, update the stats row:

```swift
            HStack(spacing: 12) {
                Label("\(detail.typesQueried) types", systemImage: "list.bullet")
                Label("\(detail.samplesCollected) samples", systemImage: "waveform.path")
                Label("\(detail.filesUploaded) uploaded", systemImage: "arrow.up.doc")
                if detail.filesSkipped > 0 {
                    Label("\(detail.filesSkipped) skipped", systemImage: "checkmark.circle")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
```

**Step 6: Build and test**

Run: `cd <worktree> && xcodebuild build -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: Build succeeds.

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All existing tests pass.

**Step 7: Commit**

```bash
git add -A
git commit -m "feat(sync): add Sync All button for full history re-sync

- New syncAll() method queries all HealthKit history
- Watermark skips unchanged files (most historical days)
- UI shows sync-all progress and skipped file count
- Both sync modes use same deterministic file format"
```

---

### Task 8: Clean Up Old File Format Remnants

Remove `SyncFilePayload`, `DeviceInfo` (if unused), and the old `raw/` path segment. Update `DaySamples` doc comment.

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift` (remove old structs)
- Modify: `MyLifeDB/DataCollect/CollectorTypes.swift` (update doc comment)

**Step 1: Remove `SyncFilePayload` and `DeviceInfo`**

In `HealthKitCollector.swift`:
- Delete `SyncFilePayload` (lines 635-645)
- Delete `DeviceInfo` (lines 648-658) — search for other usages first; if none, delete
- Delete `currentDeviceInfo()` helper (lines 605-622) if no longer called

**Step 2: Update DaySamples doc comment**

In `CollectorTypes.swift`, update the doc comment on `uploadPath` (line 20):

```swift
    /// The upload path on the backend
    /// e.g., "imports/fitness/apple-health/2026/02/09/step-count.json"
    let uploadPath: String
```

**Step 3: Build and run all tests**

Run: `cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All tests pass, no warnings about unused code.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor(sync): remove old SyncFilePayload and DeviceInfo structs"
```

---

### Task 9: Final Verification

End-to-end check that everything works together.

**Step 1: Run full test suite**

```bash
cd <worktree> && xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

Expected: All tests pass (HKTypeFileNameTests, TypeDayPayloadTests, SyncWatermarkTests, SampleDayBucketTests).

**Step 2: Build for device**

```bash
cd <worktree> && xcodebuild build -scheme MyLifeDB -destination generic/platform=iOS 2>&1 | tail -20
```

Expected: Build succeeds with no errors.

**Step 3: Verify no compiler warnings**

Check build output for warnings. Fix any.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "chore: fix warnings from deterministic sync refactor"
```
