# Workout Routes + File Structure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Flatten the `apple-health/` import structure, give workouts their own self-contained JSON files with embedded GPS routes, fix the incomplete activity type mapping, and migrate existing data.

**Architecture:** `HealthKitCollector` splits into two output streams — time-series samples (→ `sample-<ts>.json`) and workout events (→ `workout-<UUID>.json`). Workout collection runs a second pass via `HKSeriesSampleQuery` to fetch `CLLocation` points and embed them inline. A one-off shell script migrates existing `raw/` files.

**Tech Stack:** Swift, HealthKit (`HKWorkoutType`, `HKSeriesType.workoutRoute()`, `HKSeriesSampleQuery`), Swift Testing framework (`import Testing`, `@Test`, `#expect`), bash for migration.

**Working directory:** `.worktrees/workout-routes` inside `my-life-db-apple/`
**Run tests with:** `xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "passed|failed|error"`

---

## Task 1: Fix upload path — drop `raw/`, rename to `sample-`

**Goal:** Samples write to `YYYY/MM/DD/sample-<ts>.json` instead of `raw/YYYY/MM/DD/<ts>.json`.

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift` (path construction, ~line 343)
- Modify: `MyLifeDB/DataCollect/CollectorTypes.swift` (stale comment in `DaySamples.uploadPath`)
- Modify: `MyLifeDBTests/MyLifeDBTests.swift` (add test)

**Step 1: Write the failing test**

In `MyLifeDBTests/MyLifeDBTests.swift`, replace the example test:

```swift
import Testing
import Foundation

struct UploadPathTests {

    @Test func sampleUploadPathHasNoPrefixAndSamplePrefix() {
        // The path for a sample batch on 2026-02-20, synced at a known time
        let dayString = "2026-02-20"
        let syncTimestamp = "2026-02-20T09-58-48Z"

        let parts = dayString.split(separator: "-")
        let uploadPath = "\(parts[0])/\(parts[1])/\(parts[2])/sample-\(syncTimestamp).json"

        #expect(uploadPath == "2026/02/20/sample-2026-02-20T09-58-48Z.json")
        #expect(!uploadPath.hasPrefix("raw/"))
        #expect(uploadPath.contains("sample-"))
    }
}
```

**Step 2: Run test — verify it passes** (pure string logic, no HealthKit needed)

```
xcodebuild test -scheme MyLifeDB -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "passed|failed|error"
```

Expected: `Test Suite 'All tests' passed`

**Step 3: Update the upload path in `HealthKitCollector.swift`**

Find (~line 340-344):
```swift
let uploadPath = "imports/fitness/apple-health/raw/\(pathComponents[0])/\(pathComponents[1])/\(pathComponents[2])/\(syncTimestamp).json"
```

Replace with:
```swift
let uploadPath = "imports/fitness/apple-health/\(pathComponents[0])/\(pathComponents[1])/\(pathComponents[2])/sample-\(syncTimestamp).json"
```

**Step 4: Fix stale comment in `CollectorTypes.swift`**

Find in `DaySamples`:
```swift
/// e.g., "imports/fitness/apple-health/raw/2026/02/09/2026-02-09T12-00-00Z.json"
```
Replace with:
```swift
/// e.g., "imports/fitness/apple-health/2026/02/09/sample-2026-02-09T12-00-00Z.json"
/// or    "imports/fitness/apple-health/2026/02/09/workout-E3F2ABCD-….json"
```

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift \
        MyLifeDB/DataCollect/CollectorTypes.swift \
        MyLifeDBTests/MyLifeDBTests.swift
git commit -m "refactor: flatten apple-health path, rename to sample-<ts>.json"
```

---

## Task 2: Expand + fix workout activity type mapping

**Goal:** Replace the 7-entry table with all ~80 known `HKWorkoutActivityType` raw values. Fixes `unknown_4` (badminton) and the existing `35: "yoga"` bug (35 = rowing, 57 = yoga).

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift` (`workoutActivityTypeNames`, ~line 55)
- Modify: `MyLifeDBTests/MyLifeDBTests.swift` (add test)

**Step 1: Write the failing test**

Add to `MyLifeDBTests.swift`:

```swift
struct ActivityTypeTests {
    // Mirror the mapping from HealthKitCollector for testing
    let names: [UInt: String] = workoutActivityTypeNamesForTesting

    @Test func badmintonIsNotUnknown() {
        #expect(names[4] == "badminton")
    }

    @Test func rowingIsNotYoga() {
        #expect(names[35] == "rowing")
        #expect(names[57] == "yoga")
    }

    @Test func noUnknownValuesForCommonTypes() {
        let commonTypes: [UInt] = [1,4,13,24,37,46,52,57,63]
        for type_ in commonTypes {
            #expect(names[type_] != nil, "Type \(type_) should be mapped")
        }
    }
}
```

Because `workoutActivityTypeNames` is private, extract it to an `internal` `let` at file scope for testing:
```swift
// In HealthKitCollector.swift, above the class declaration:
let workoutActivityTypeNamesForTesting: [UInt: String] = _workoutActivityTypeNames
```
And rename the private property to `_workoutActivityTypeNames` (or use `@testable import`).

Actually simpler: add `@testable import MyLifeDB` to the test file and make the dict `internal` (remove `private`).

**Step 2: Run test — verify it fails**

Expected: `rowingIsNotYoga` FAILS (current mapping has 35: "yoga")

**Step 3: Replace the mapping in `HealthKitCollector.swift`**

Replace the entire `workoutActivityTypeNames` dictionary:

```swift
private let workoutActivityTypeNames: [UInt: String] = [
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
    82:   "swimBikeRun",
    83:   "transition",
    3000: "other",
]
```

**Step 4: Run tests — verify they pass**

Expected: all 3 activity type tests pass.

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift \
        MyLifeDBTests/MyLifeDBTests.swift
git commit -m "fix: expand workout activity type mapping, fix 35=rowing (was yoga)"
```

---

## Task 3: Extract workout encoder — new `WorkoutFile` struct

**Goal:** Define the JSON schema for `workout-<UUID>.json` files. Pure data types, no HealthKit dependency — fully testable.

**Files:**
- Create: `MyLifeDB/DataCollect/Collectors/WorkoutFile.swift`
- Modify: `MyLifeDBTests/MyLifeDBTests.swift` (add test)

**Step 1: Write the failing test**

```swift
import Testing
import Foundation

struct WorkoutFileTests {

    @Test func routePointEncodesAllFields() throws {
        let point = RoutePoint(
            timestamp: Date(timeIntervalSince1970: 0),
            lat: 31.234567, lon: 121.456789,
            alt: 12.4,
            hAcc: 3.2, vAcc: 4.1,
            speed: 2.8, speedAcc: 0.3,
            course: 273.5, courseAcc: 5.0
        )
        let data = try JSONEncoder().encode(point)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["lat"] as? Double == 31.234567)
        #expect(json["lon"] as? Double == 121.456789)
        #expect(json["alt"] as? Double == 12.4)
        #expect(json["h_acc"] as? Double == 3.2)
        #expect(json["speed"] as? Double == 2.8)
        #expect(json["t"] != nil)
    }

    @Test func workoutFileWithNoRouteEncodesRouteAsNull() throws {
        let workout = WorkoutFile(
            uuid: "test-uuid",
            activityType: "running",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3600),
            durationS: 3600,
            source: "com.apple.health",
            device: "Watch7,1",
            syncedAt: Date(timeIntervalSince1970: 0),
            deviceInfo: DeviceInfo(name: "Watch", model: "Watch", systemVersion: "11.0"),
            stats: [:],
            metadata: nil,
            route: nil
        )
        let data = try JSONEncoder().encode(workout)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["uuid"] as? String == "test-uuid")
        #expect(json["activity_type"] as? String == "running")
        #expect(json["duration_s"] as? Double == 3600)
        // route key should be absent when nil
        #expect(json["route"] == nil)
    }
}
```

**Step 2: Run test — verify it fails** (types don't exist yet)

**Step 3: Create `WorkoutFile.swift`**

```swift
//
//  WorkoutFile.swift
//  MyLifeDB
//
//  JSON schema for workout-<UUID>.json files.
//  One file per workout event, with embedded GPS route.
//

import Foundation

/// A raw GPS point from HKWorkoutRoute / CLLocation.
/// All fields stored as-is — no downsampling.
struct RoutePoint: Encodable {
    let timestamp: Date
    let lat: Double
    let lon: Double
    let alt: Double
    let hAcc: Double   // horizontal accuracy, metres
    let vAcc: Double   // vertical accuracy, metres
    let speed: Double  // m/s, negative = invalid
    let speedAcc: Double
    let course: Double // degrees clockwise from north, negative = invalid
    let courseAcc: Double

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case lat, lon, alt
        case hAcc = "h_acc"
        case vAcc = "v_acc"
        case speed
        case speedAcc = "speed_acc"
        case course
        case courseAcc = "course_acc"
    }
}

/// A stat value with its unit (e.g. energy: 435 kcal).
struct StatValue: Encodable {
    let value: Double
    let unit: String
}

/// Top-level structure for a workout-<UUID>.json file.
struct WorkoutFile: Encodable {
    let uuid: String
    let activityType: String
    let start: Date
    let end: Date
    let durationS: Double
    let source: String
    let device: String?
    let syncedAt: Date
    let deviceInfo: DeviceInfo
    let stats: [String: StatValue]
    let metadata: [String: Any]?
    let route: [RoutePoint]?   // nil = no GPS (indoor workout)

    enum CodingKeys: String, CodingKey {
        case uuid
        case activityType = "activity_type"
        case start, end
        case durationS = "duration_s"
        case source, device
        case syncedAt = "synced_at"
        case deviceInfo = "device_info"
        case stats, metadata, route
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid,         forKey: .uuid)
        try c.encode(activityType, forKey: .activityType)
        try c.encode(start,        forKey: .start)
        try c.encode(end,          forKey: .end)
        try c.encode(durationS,    forKey: .durationS)
        try c.encode(source,       forKey: .source)
        try c.encodeIfPresent(device,     forKey: .device)
        try c.encode(syncedAt,     forKey: .syncedAt)
        try c.encode(deviceInfo,   forKey: .deviceInfo)
        try c.encode(stats,        forKey: .stats)
        try c.encodeIfPresent(route, forKey: .route)
        if let metadata, !metadata.isEmpty {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            try c.encode(AnyCodable(jsonObject), forKey: .metadata)
        }
    }
}
```

Note: `AnyCodable` and `DeviceInfo` are already defined in `HealthKitCollector.swift` — move `DeviceInfo` to a shared file (or just keep `WorkoutFile.swift` in the same module so it can access them).

**Step 4: Run tests — verify they pass**

**Step 5: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/WorkoutFile.swift \
        MyLifeDBTests/MyLifeDBTests.swift
git commit -m "feat: add WorkoutFile + RoutePoint schema for workout-UUID.json"
```

---

## Task 4: Add workout collection method to `HealthKitCollector`

**Goal:** New `collectWorkouts(since:)` method that queries `HKWorkout` samples, fetches each workout's GPS route via `HKSeriesSampleQuery`, and returns `[DaySamples]` with `workout-<UUID>.json` upload paths.

**Files:**
- Modify: `MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift`

**Step 1: Skip `HKWorkout` in the existing sample batch**

In `encodeSample(_:)`, find the `if let workout = sample as? HKWorkout` block and change it to return `nil`:

```swift
// Workouts are exported as standalone workout-<UUID>.json files,
// not as entries in the sample batch.
if sample is HKWorkout {
    return nil
}
```

This removes workouts from `sample-<ts>.json` files.

**Step 2: Add `collectWorkouts(since:)` method**

Add this method to `HealthKitCollector`, before `// MARK: - HealthKit Queries`:

```swift
// MARK: - Workout Collection

private let workoutAnchorKey = "sync.anchor.healthkit.workouts"

private func loadWorkoutAnchorDate() -> Date? {
    UserDefaults.standard.object(forKey: workoutAnchorKey) as? Date
}

func saveWorkoutAnchorDate(_ date: Date) {
    UserDefaults.standard.set(date, forKey: workoutAnchorKey)
}

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
    let syncTimestamp = ISO8601DateFormatter().string(from: Date())
        .replacingOccurrences(of: ":", with: "-")
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

        // Fetch GPS route (may be nil for indoor workouts)
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
/// Returns nil if the workout has no associated route (e.g. indoor).
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
        let q = HKSeriesSampleQuery(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObject(with: route.uuid)) { _, locations, done, error in
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
```

**Step 3: Wire `collectWorkouts` into `collectNewSamples()`**

At the end of `collectNewSamples()`, before `return CollectionResult(...)`:

```swift
// Also collect workouts (separate files, separate anchor)
let workoutStart = loadWorkoutAnchorDate()
    ?? Calendar.current.date(byAdding: .day, value: -initialLookbackDays, to: Date())!
let workoutBatches = (try? await collectWorkouts(since: workoutStart)) ?? []
batches.append(contentsOf: workoutBatches)
```

Update `commitAnchor(for:)` to also save the workout anchor:

```swift
func commitAnchor(for batch: DaySamples) async {
    if let date = batch.anchorToken as? Date {
        // Update whichever anchor is older
        saveAnchorDate(date)
        // If this is a workout batch, also advance workout anchor
        if batch.uploadPath.contains("/workout-") {
            saveWorkoutAnchorDate(date)
        }
    }
}
```

**Step 4: Request route authorization**

In `requestAuthorization()`, add `HKSeriesType.workoutRoute()` to the read types when `workout_routes` is enabled. Add to `hkTypes(for:)`:

```swift
case "workout_routes": return [HKSeriesType.workoutRoute()]
```

**Step 5: Manual verification on device**

Build and run on iPhone. Navigate to Data Collect → enable Workouts + Workout Routes → tap Sync Now. Check that:
- `imports/fitness/apple-health/2026/02/XX/workout-<UUID>.json` files appear
- Each workout file contains `activity_type`, `stats`, `route` (non-null for outdoor workouts)
- Workout entries are absent from `sample-*.json` files
- Indoor workouts have `"route": null` or no route key

**Step 6: Commit**

```bash
git add MyLifeDB/DataCollect/Collectors/HealthKitCollector.swift
git commit -m "feat: collect workouts as standalone files with embedded GPS route"
```

---

## Task 5: Update `DataCollectView` — workout_routes status

**Files:**
- Modify: `MyLifeDB/Views/Me/DataCollectView.swift`

**Step 1: Update description**

Find:
```swift
DataSource(id: "workout_routes", name: "Workout Routes", icon: "map.fill", description: "GPS tracks for outdoor workouts", platform: .iOSWatch, status: .available),
```

Update description to reflect the new behaviour:
```swift
DataSource(id: "workout_routes", name: "Workout Routes", icon: "map.fill", description: "GPS tracks for outdoor workouts — stored inside each workout file", platform: .iOSWatch, status: .available),
```

**Step 2: Commit**

```bash
git add MyLifeDB/Views/Me/DataCollectView.swift
git commit -m "chore: update workout_routes description in DataCollectView"
```

---

## Task 6: Migration script — rename existing `raw/` files

**Goal:** Move `imports/fitness/apple-health/raw/YYYY/MM/DD/<ts>.json` → `imports/fitness/apple-health/YYYY/MM/DD/sample-<ts>.json`.

**Files:**
- Create: `scripts/migrate-raw-to-flat.sh` (in `my-life-db-apple` repo)

**Step 1: Write the script**

Create `scripts/migrate-raw-to-flat.sh`:

```bash
#!/usr/bin/env bash
# Migrates apple-health/raw/YYYY/MM/DD/<ts>.json
#         → apple-health/YYYY/MM/DD/sample-<ts>.json
#
# Usage: ./scripts/migrate-raw-to-flat.sh <data-dir>
# Example: ./scripts/migrate-raw-to-flat.sh ~/my-life-db/data

set -euo pipefail

DATA_DIR="${1:?Usage: $0 <data-dir>}"
APPLE_HEALTH="$DATA_DIR/imports/fitness/apple-health"
RAW_DIR="$APPLE_HEALTH/raw"

if [ ! -d "$RAW_DIR" ]; then
    echo "Nothing to migrate: $RAW_DIR does not exist"
    exit 0
fi

moved=0
skipped=0

while IFS= read -r -d '' src; do
    # src = .../raw/2026/02/20/2026-02-20T09-58-48Z.json
    rel="${src#$RAW_DIR/}"                  # 2026/02/20/2026-02-20T09-58-48Z.json
    dir=$(dirname "$rel")                   # 2026/02/20
    filename=$(basename "$rel")             # 2026-02-20T09-58-48Z.json
    dest_dir="$APPLE_HEALTH/$dir"
    dest="$dest_dir/sample-$filename"

    mkdir -p "$dest_dir"

    if [ -f "$dest" ]; then
        echo "SKIP (exists): $dest"
        ((skipped++))
        continue
    fi

    mv "$src" "$dest"
    echo "MOVED: raw/$rel → $dir/sample-$filename"
    ((moved++))
done < <(find "$RAW_DIR" -name "*.json" -print0)

echo ""
echo "Done. Moved: $moved, Skipped: $skipped"

# Remove raw/ if now empty
if [ -z "$(find "$RAW_DIR" -name "*.json" 2>/dev/null)" ]; then
    rm -rf "$RAW_DIR"
    echo "Removed empty raw/ directory"
fi
```

**Step 2: Test the script with a dry run**

```bash
chmod +x scripts/migrate-raw-to-flat.sh

# Dry-run: count files to be migrated
find ~/my-life-db/data/imports/fitness/apple-health/raw -name "*.json" | wc -l
```

Expected: number of files to migrate (around 100+).

**Step 3: Run the migration**

```bash
./scripts/migrate-raw-to-flat.sh ~/my-life-db/data
```

Verify:
```bash
# raw/ should be gone
ls ~/my-life-db/data/imports/fitness/apple-health/

# sample- prefix files should be present
ls ~/my-life-db/data/imports/fitness/apple-health/2026/02/20/ | head -5
```

Expected output: files named `sample-2026-02-20T…Z.json`, no `raw/` directory.

**Step 4: Commit script + verify data**

```bash
git add scripts/migrate-raw-to-flat.sh
git commit -m "chore: add migration script, rename raw/ files to sample-<ts>.json"
```

---

## Task 7: Push + clean up

```bash
# From repo root
git fetch origin
cd .worktrees/workout-routes
git rebase origin/main
git push origin workout-routes:main

cd ../..
git pull --rebase origin main
git worktree remove .worktrees/workout-routes
git branch -d workout-routes
```
