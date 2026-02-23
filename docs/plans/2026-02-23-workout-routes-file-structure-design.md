# Design: Workout Routes + File Structure Overhaul

**Date:** 2026-02-23
**Status:** Approved

## Problem

1. The current `raw/` subdirectory is an unnecessary layer — `apple-health/raw/YYYY/MM/DD/` vs a cleaner `apple-health/YYYY/MM/DD/`.
2. Workouts are stored as regular samples inside `sample-*.json` batch files, mixed with heart rate, steps, etc. A workout is a self-contained event (not a time-series measurement) and deserves its own file.
3. `HKWorkoutRoute` (GPS tracks) is not collected at all.
4. The workout activity type mapping is incomplete — uncommon types fall back to `"unknown_<N>"`.
5. Workout records don't store their HealthKit UUID, making cross-referencing impossible.

---

## Decisions

### 1. Flat date-based folder structure (no type subdirectory)

```
imports/fitness/apple-health/
└── YYYY/MM/DD/
    ├── sample-<ISO-timestamp>.json    ← HealthKit time-series samples
    └── workout-<UUID>.json            ← one file per workout event
```

- No `raw/` layer.
- Filename prefix makes the file type explicit without opening it.
- Extensible: `mood-…`, `ecg-…`, etc. can follow the same pattern later.

### 2. Workouts are separate files, not samples

Workouts are removed from the `sample-*.json` batch entirely. Each workout gets its own `workout-<UUID>.json` file containing all data for that event.

### 3. Route embedded inside the workout file

GPS points are stored inline in the workout file. Raw principle: every `CLLocation` field is stored, no downsampling.

```json
{
  "uuid":          "E3F2ABCD-…",
  "activity_type": "running",
  "start":         "2026-02-20T08:47:23Z",
  "end":           "2026-02-20T09:41:28Z",
  "duration_s":    3245.2,
  "source":        "com.apple.health.…",
  "device":        "Watch7,1",
  "synced_at":     "2026-02-20T09:58:48Z",
  "device_info":   { "name": "…", "model": "…", "system_version": "…" },
  "stats": {
    "active_energy_burned": { "value": 435.07, "unit": "kcal" },
    "distance":             { "value": 2531.6,  "unit": "m"   }
  },
  "metadata": {
    "HKIndoorWorkout": 0,
    "HKTimeZone": "Asia/Shanghai",
    "HKWeatherHumidity": 47
  },
  "route": [
    {
      "t":          "2026-02-20T08:47:25Z",
      "lat":        31.234567,
      "lon":        121.456789,
      "alt":        12.4,
      "h_acc":      3.2,
      "v_acc":      4.1,
      "speed":      2.8,
      "speed_acc":  0.3,
      "course":     273.5,
      "course_acc": 5.0
    }
  ]
}
```

- `route` is `null` or omitted if the workout has no GPS data (indoor workouts).
- Route query uses `HKSeriesSampleQuery` on the `HKWorkoutRoute` associated with each workout.

### 4. Complete activity type mapping

The `workoutActivityTypeNames` table is expanded to cover all known `HKWorkoutActivityType` raw values (1–83 + 3000), eliminating `"unknown_N"` for all standard types.

### 5. Workout anchor tracked separately

Route collection needs to re-visit workouts from the beginning (routes may not have been fetched in previous syncs). A separate `sync.anchor.healthkit.workouts` UserDefaults key tracks the last workout sync date, independent of the sample anchor.

---

## Migration

Existing files under `raw/YYYY/MM/DD/<timestamp>.json` are renamed and moved:

```
raw/2026/02/20/2026-02-20T09-58-48Z.json
  → 2026/02/20/sample-2026-02-20T09-58-48Z.json
```

Migration runs as a one-off script on the Mac mini against the life-db data directory. The `raw/` folder is removed after migration.

Existing workout samples embedded inside the old `raw/` files are **not** extracted — they stay in those files as historical record. New syncs will produce proper `workout-<UUID>.json` files going forward. The overlap period is short (data only goes back ~2 weeks).

---

## iOS Implementation Scope

1. **`HealthKitCollector.swift`**
   - Change upload path from `raw/YYYY/MM/DD/<ts>.json` → `YYYY/MM/DD/sample-<ts>.json`
   - Skip `HKWorkout` samples in the main sample batch
   - Add `WorkoutCollector` (or method) to query workouts + routes:
     - `HKSampleQuery` for `HKWorkoutType`
     - Per workout: `HKAnchoredObjectQuery` for `HKWorkoutRoute` → `HKSeriesSampleQuery` for `CLLocation` points
     - Write `YYYY/MM/DD/workout-<UUID>.json`
   - Expand `workoutActivityTypeNames` to all known types
   - Store workout UUID in encoded output

2. **`DataCollectView.swift`** — update `workout_routes` source description to "Available"

3. **Migration script** — shell or Swift script to rename `raw/` files on the Mac mini

---

## Out of Scope

- Extracting old workout samples from historical `raw/` files into `workout-*.json`
- Mood / State of Mind (backlog item 1)
