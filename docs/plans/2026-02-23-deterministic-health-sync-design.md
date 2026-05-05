# Deterministic Health Sync

## Problem

The current sync produces non-deterministic files:
- Files named by sync timestamp (`2026-02-09T10-00-00Z.json`), not by content
- Same day's data produces different files depending on when you sync
- Re-syncing creates duplicate files instead of overwriting
- Enabling a new category only syncs from the global anchor, losing historical data
- No way to do a clean full re-sync without duplicating everything

## Design

### File layout

One file per HealthKit type per day. No data → no file.

```
imports/fitness/apple-health/
└── 2026/
    └── 02/
        └── 09/
            ├── step-count.json
            ├── heart-rate.json
            ├── heart-rate-variability-sdnn.json
            ├── resting-heart-rate.json
            ├── sleep-analysis.json
            └── workout-running.json
```

**Naming**: strip HK prefix (`HKQuantityTypeIdentifier`, `HKCategoryTypeIdentifier`), convert to kebab-case. Workouts: `workout-<activity-type>.json`.

**Day boundary**: sample's own timezone (from HealthKit metadata `HKTimeZone`). Fallback to device timezone if metadata missing.

### File format

Stripped down for determinism — no `syncedAt`, no top-level `deviceInfo`:

```json
{
  "type": "HKQuantityTypeIdentifierStepCount",
  "date": "2026-02-09",
  "timezone": "Asia/Singapore",
  "unit": "count",
  "samples": [
    {
      "start": "2026-02-09T00:15:00+08:00",
      "end": "2026-02-09T00:30:00+08:00",
      "value": 42,
      "source": "com.apple.health.9A1B2C",
      "device": "iPhone 15 Pro",
      "metadata": null
    }
  ]
}
```

**Determinism guarantees:**
- Samples sorted by `(start, end, source)` — deterministic ordering
- JSON encoder uses sorted keys
- Consistent ISO8601 dates with timezone offset
- `unit` hoisted to top level (same for all samples in a quantity-type file)
- Same HealthKit data → same bytes → same hash

### Sync mechanism

One code path, two date ranges:

| | Regular sync | Sync All |
|--|--|--|
| Range | `anchor.startOfDay` → now | All HealthKit history → now |
| Trigger | Foreground / background / manual | Manual button ("Sync All") |
| Speed | Fast (1-2 days) | Slow (background, can be years of data) |

Both modes do the same thing:

1. **Query** each enabled HK type for the full calendar day (midnight to midnight, or midnight to now for today)
2. **Build** one file per type per day — complete snapshot, not incremental
3. **Watermark** — hash each file locally, compare with last uploaded hash, skip unchanged
4. **Upload** changed files (PUT overwrites existing)
5. **Advance anchor** to now (regular sync only; Sync All resets it)

### How multiple syncs per day work

Each sync rebuilds today's files from midnight. The file grows as the day progresses:

```
10am sync:  step-count.json (500 samples)  hash=abc → upload
 3pm sync:  step-count.json (800 samples)  hash=def → upload (changed)
 3pm sync:  body-mass.json  (1 sample)     hash=aaa → skip (unchanged)
10pm sync:  step-count.json (1200 samples) hash=ghi → upload (changed)
```

Past days are stable — watermark almost always skips them.

### Anchor behavior

The anchor determines which days to rebuild:

```
anchor = Feb 22 10pm → affected days = [Feb 22, Feb 23 (today)]
```

Always includes anchor's day (catches late-arriving data from that day) plus today.

### New category → Sync All

When a user enables a new health category, they press "Sync All". This queries all history for all enabled types, builds complete day files, and watermarks skip the types that haven't changed. Only the newly enabled type's files get uploaded.

### Local watermark storage

Per-file hash stored in UserDefaults (or a small local dict):

```
Key: "sync.watermark.<upload-path>"
Value: SHA-256 hash of last successfully uploaded file contents
```

Cleared on "Sync All" to force re-upload of everything (optional — even without clearing, identical files produce identical hashes and get skipped).

### What changes from current implementation

| Component | Current | New |
|-----------|---------|-----|
| File path | `YYYY/MM/DD/<sync-timestamp>.json` | `YYYY/MM/DD/<hk-type-kebab>.json` |
| File content | All types mixed, includes `syncedAt` + `deviceInfo` | One type per file, data-only |
| Grouping | By calendar day, all types together | By calendar day × HK type |
| Upload behavior | Always creates new file | Overwrites same path (deterministic) |
| Skip logic | None (always uploads) | Hash watermark skips unchanged |
| Day boundary | Device calendar at sync time | Sample's own timezone |
| New category | Syncs from global anchor (loses history) | User hits Sync All (gets everything) |
| Full re-sync | Not possible without duplicating | Sync All — safe, idempotent |
