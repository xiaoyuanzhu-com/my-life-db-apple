# Backlog

## 1. Mood / State of Mind (iOS 18+)

`case "mood": return []` is currently an empty stub.

iOS 18 introduced `HKStateOfMind` — a new sample type that isn't a standard `HKQuantityType` or `HKCategoryType`. It requires a dedicated `HKStateOfMindType.stateOfMindType()` query, an `@available(iOS 18.0, *)` guard, and custom encoding (the sample carries `valence`, `valenceClassification`, `kind`, and `labels` fields). Needs separate design + implementation.
