//
//  HKTypeFileName.swift
//  MyLifeDB
//
//  Converts HealthKit type identifiers to deterministic kebab-case filenames.
//  Used to generate stable, predictable file names for each HK data type.
//
//  Examples:
//    "HKQuantityTypeIdentifierStepCount"   → "step-count"
//    "HKCategoryTypeIdentifierSleepAnalysis" → "sleep-analysis"
//    "HKWorkoutTypeIdentifier"              → "workout"
//

import Foundation

enum HKTypeFileName {

    /// Known HealthKit type identifier prefixes, ordered longest-first
    /// so more-specific prefixes match before shorter ones.
    private static let knownPrefixes = [
        "HKQuantityTypeIdentifier",
        "HKCategoryTypeIdentifier",
        "HKCorrelationTypeIdentifier",
        "HKWorkoutTypeIdentifier",
        "HKDataTypeIdentifier",
    ]

    /// Converts an HK type identifier string to a kebab-case filename stem.
    ///
    /// Strips the known prefix (e.g. `HKQuantityTypeIdentifier`) and converts
    /// the remaining PascalCase/camelCase suffix to kebab-case.
    /// If the identifier uses an unknown prefix pattern, falls back to
    /// stripping everything up to and including "TypeIdentifier".
    /// If nothing remains after stripping (e.g. `HKWorkoutTypeIdentifier`),
    /// returns `"workout"`.
    static func fileName(for hkIdentifier: String) -> String {
        var name = hkIdentifier

        // Try known prefixes first
        var matched = false
        for prefix in knownPrefixes {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                matched = true
                break
            }
        }

        // Fallback: strip everything up to and including "TypeIdentifier"
        if !matched, let range = name.range(of: "TypeIdentifier") {
            name = String(name[range.upperBound...])
        }

        if name.isEmpty { return "workout" }
        return camelToKebab(name)
    }

    /// Generates a workout filename for a specific activity type.
    ///
    /// Example: `workoutFileName(activityName: "running")` → `"workout-running"`
    static func workoutFileName(activityName: String) -> String {
        "workout-\(camelToKebab(activityName))"
    }

    // MARK: - Private

    /// Converts a PascalCase or camelCase string to kebab-case.
    ///
    /// Handles consecutive uppercase runs (acronyms like "SDNN")
    /// and digits (like "VO2Max" → "vo2-max").
    private static func camelToKebab(_ input: String) -> String {
        var result = ""
        let chars = Array(input)

        for i in chars.indices {
            let c = chars[i]
            if c.isUppercase {
                let prevIsLower = i > 0 && chars[i - 1].isLowercase
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                let prevIsDigit = i > 0 && chars[i - 1].isNumber

                // Insert hyphen before this uppercase letter when:
                // - previous char was lowercase (camelCase boundary)
                // - previous char was a digit (e.g. "2M" in "VO2Max")
                // - next char is lowercase AND previous was uppercase
                //   (end of acronym, e.g. the "N" before "ew" in "SDNew")
                if !result.isEmpty
                    && (prevIsLower || prevIsDigit || (nextIsLower && i > 0 && chars[i - 1].isUppercase))
                {
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
