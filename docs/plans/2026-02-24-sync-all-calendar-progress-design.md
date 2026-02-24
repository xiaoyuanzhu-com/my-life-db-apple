# Health Data Sync All — Calendar Grid Progress

**Date:** 2026-02-24
**Status:** Approved
**Scope:** iOS app only (no backend changes)

## Problem

"Sync All History" shows a loading spinner with no visibility into progress. For users with years of health data, this means minutes of staring at a spinner with no feedback. The feature works correctly but the UX is unacceptable.

## Solution

Replace the opaque spinner with a **calendar grid progress view** — a new full-page screen showing every day as a date number in a Mon–Sun calendar layout. Dates turn green progressively as each day's data syncs. The sync engine changes from one giant 50-year query to month-by-month chunks, enabling real-time per-day progress updates.

## Design

### Navigation Changes

**DataCollectView** button layout changes from:

```
[ Sync Now ]  [ Sync All History ]     (side by side)
```

To:

```
[ Sync Now ]                            (primary, prominent)

Sync All History →                      (secondary text link, second line)
```

Tapping "Sync All History →" navigates to the new **SyncDataView**. The sync does not start automatically — the user taps "Start" on the data page.

### SyncDataView — Calendar Grid

A full-page scrollable view showing health data sync progress as a calendar grid:

```
┌────────────────────────────────────────────┐
│  ← Data Collect       Health Data Sync     │
│                                             │
│  47 types · 2021–2026         [ Start ]    │
│                                             │
│  2021  ●                                    │
│  ── January ● ──────────────────────────── │
│   M   T   W   T   F   S   S               │
│               1   2   3                    │
│   4   5   6   7   8   9  10               │
│  11  12  13  14  15  16  17               │
│  18  19  20  21  22  23  24               │
│  25  26  27  28  29  30  31               │
│                                             │
│  ── February ● ────────────────────────── │
│   M   T   W   T   F   S   S               │
│   1   2   3   4   5   6   7               │
│   8   9  10  11  12  13  14               │
│  ...                                        │
│                                             │
│  2022  ◐                                    │
│  ── January ● ──────────────────────────── │
│   (all dates green)                        │
│                                             │
│  ── February ──────────────────────────── │
│   M   T   W   T   F   S   S               │
│   1   2   3   4   5   6   7               │
│   8   9  10  11  12  13  14               │
│  15  16  17  18  19  20  21               │
│  22  23  24  25  26  27  28               │
│       ↑green  ↑pulsing  ↑dim              │
│                                             │
│  2023                                       │
│  ── January ────────────────────────────── │
│  ...                                        │
└────────────────────────────────────────────┘
```

**Layout:**
- All years and months expanded by default — one long scrollable page
- Each month is a standard Mon–Sun calendar grid with date numbers
- Years are section headers with a small dot indicator
- Months are sub-headers with a small dot indicator

**Date number states (visual):**
- **Dim (gray text)** — not yet synced (pending)
- **Pulsing** — currently syncing this day
- **Green text** — synced successfully
- **Red text** — error (tappable for details)

**Header dot states:**
- **Absent** — all children pending
- **Pulsing** — sync in progress within this year/month
- **Green ●** — all children complete
- **Red ●** — one or more children have errors

**Interactions:**
- Tap "Start" to begin sync
- Tap a red date to see error details
- "Retry Failed" button appears at top if any errors exist
- Back navigation returns to DataCollectView (sync continues)
- The view is scrollable — user scrolls to whichever year/month they want to inspect

### Design Principles

- **Monochrome with green.** No colorful icons, no emoji. Status communicated through text color (dim/green/red) and small dots.
- **Minimal text.** No file counts, no log lines, no verbose status messages. The calendar grid is the entire story.
- **Calm.** The progressive fill of green dates gives feedback without demanding attention.

## Sync Engine Changes

### Current Flow (to be replaced for Sync All)

```
syncAll() → query 50 years per type → group by (day, type) → upload all
```

Single giant query, no per-day feedback, high memory usage, not resumable.

### New Flow: Month-Chunked Sync

**Phase 1 — Discovery (fast):**
- Query HealthKit for the earliest sample date across all enabled types
- Determine the year range (e.g., 2021-01 to 2026-02)
- Build the full calendar model and populate the grid (all dates dim)

**Phase 2 — Month-by-month execution (oldest first):**

```
for each month from earliest to current:
    query HealthKit for all enabled types within this month
    group results by (day, type)
    for each day:
        for each type file:
            check watermark (skip if unchanged)
            upload via PUT /raw/imports/fitness/apple-health/YYYY/MM/DD/<type>.json
        mark date green
    mark month dot green
mark year dot green
```

**Key properties:**
- HealthKit queried one month at a time — bounded memory
- Progress visible per day as uploads complete
- Oldest to newest order
- Same backend endpoint, same file format, same watermark logic

### Pause/Resume

- Persist completed months to UserDefaults (set of `"YYYY-MM"` strings)
- On re-open or restart, the grid loads with previously completed months already green
- Sync resumes from the first incomplete month
- The "Start" button becomes "Resume" if prior progress exists

### Relationship to Incremental Sync

- "Sync Now" (incremental) is **unchanged** — still uses anchor-based queries for recent data
- "Sync All" uses the new month-chunked flow
- Both update the same watermark store — no duplicate uploads
- After a full "Sync All" completes, subsequent "Sync Now" calls only fetch new data (as before)

## Error Handling

- If a day fails to sync → date turns red, sync continues to next day
- Month/year dots reflect worst child state (one red day = red month dot)
- "Retry Failed" button at top retries only failed days
- Tapping a red date shows error message in a popover
- Network errors are retried with exponential backoff before marking as failed

## Scope

### In Scope (iOS app only)
- New `SyncDataView` with calendar grid
- Month-chunked `HealthKitCollector` for full sync
- Sync progress persistence (UserDefaults)
- DataCollectView button layout changes
- Pause/resume support

### Out of Scope
- Backend changes (none needed)
- Changes to incremental "Sync Now"
- Data browsing or charts (future enhancement)
- Other data collectors (only HealthKit currently)
