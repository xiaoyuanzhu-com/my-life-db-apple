//
//  TypeDayPayloadTests.swift
//  MyLifeDBTests
//
//  Tests for TypeDayPayload deterministic per-type-per-day JSON encoding.
//

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
