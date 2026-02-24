//
//  SampleDayBucketTests.swift
//  MyLifeDBTests
//
//  Tests for timezone-aware day bucketing of HealthKit samples.
//

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
