//
//  SampleDayBucket.swift
//  MyLifeDB
//
//  Extracts the calendar day string from a HealthKit sample's start date,
//  using the sample's timezone from HealthKit metadata (key: "HKTimeZone").
//  Falls back to the device's current timezone when metadata is absent or invalid.
//

import Foundation

enum SampleDayBucket {

    struct DayKey: Hashable {
        let date: String      // "YYYY-MM-DD"
        let timezone: String  // IANA identifier
    }

    /// Determines the calendar day a sample belongs to, respecting the timezone
    /// recorded in HealthKit metadata.
    ///
    /// - Parameters:
    ///   - sampleStart: The sample's start date (always in UTC internally).
    ///   - metadata: The sample's metadata dictionary; may contain `"HKTimeZone"`.
    /// - Returns: A `DayKey` with the formatted date and resolved timezone identifier.
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

    /// Formats a date as "YYYY-MM-DD" in the given timezone.
    static func formatDate(_ date: Date, in tz: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
