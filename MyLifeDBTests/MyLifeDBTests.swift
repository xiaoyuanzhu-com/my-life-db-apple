//
//  MyLifeDBTests.swift
//  MyLifeDBTests
//
//  Created by Li Zhao on 2025/12/9.
//

import Testing
import Foundation
@testable import MyLifeDB

struct UploadPathTests {

    @Test func deterministicUploadPathShape() {
        // Mirror the path construction used in HealthKitCollector.collectNewSamples()
        let dayString = "2026-02-20"
        let fileBase = HKTypeFileName.fileName(for: "HKQuantityTypeIdentifierStepCount")
        let parts = dayString.split(separator: "-")

        let uploadPath = "imports/fitness/apple-health/\(parts[0])/\(parts[1])/\(parts[2])/\(fileBase).json"

        #expect(uploadPath == "imports/fitness/apple-health/2026/02/20/step-count.json")
        #expect(!uploadPath.contains("/raw/"))
        #expect(uploadPath.hasSuffix(".json"))
    }
}

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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(point)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["lat"] as? Double == 31.234567)
        #expect(json["lon"] as? Double == 121.456789)
        #expect(json["alt"] as? Double == 12.4)
        #expect(json["h_acc"] as? Double == 3.2)
        #expect(json["v_acc"] as? Double == 4.1)
        #expect(json["speed"] as? Double == 2.8)
        #expect(json["speed_acc"] as? Double == 0.3)
        #expect(json["course"] as? Double == 273.5)
        #expect(json["course_acc"] as? Double == 5.0)
        #expect(json["t"] != nil)  // ISO 8601 timestamp string
    }

    @Test func workoutFileWithNoRouteOmitsRouteKey() throws {
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workout)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["uuid"] as? String == "test-uuid")
        #expect(json["activity_type"] as? String == "running")
        #expect(json["duration_s"] as? Double == 3600)
        #expect(json["route"] == nil)  // route key absent when nil
    }

    @Test func workoutFileWithRouteEncodesPoints() throws {
        let route = [RoutePoint(
            timestamp: Date(timeIntervalSince1970: 1000),
            lat: 31.0, lon: 121.0,
            alt: 5.0,
            hAcc: 2.0, vAcc: 3.0,
            speed: 1.5, speedAcc: 0.2,
            course: 90.0, courseAcc: 3.0
        )]
        let workout = WorkoutFile(
            uuid: "route-uuid",
            activityType: "cycling",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3600),
            durationS: 3600,
            source: "com.apple.health",
            device: nil,
            syncedAt: Date(timeIntervalSince1970: 0),
            deviceInfo: DeviceInfo(name: "iPhone", model: "iPhone", systemVersion: "18.0"),
            stats: ["distance": StatValue(value: 5000, unit: "m")],
            metadata: nil,
            route: route
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workout)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["uuid"] as? String == "route-uuid")
        let routeArray = json["route"] as? [[String: Any]]
        #expect(routeArray != nil)
        #expect(routeArray?.count == 1)
        #expect(routeArray?.first?["lat"] as? Double == 31.0)

        let statsDict = json["stats"] as? [String: Any]
        #expect(statsDict != nil)
        let distStat = statsDict?["distance"] as? [String: Any]
        #expect(distStat?["value"] as? Double == 5000)
        #expect(distStat?["unit"] as? String == "m")
    }
}

struct ActivityTypeTests {

    @Test func badmintonIsNotUnknown() {
        #expect(HealthKitCollector().workoutActivityTypeNames[4] == "badminton")
    }

    @Test func rowingIsNotYoga() {
        #expect(HealthKitCollector().workoutActivityTypeNames[35] == "rowing")
        #expect(HealthKitCollector().workoutActivityTypeNames[57] == "yoga")
    }

    @Test func commonTypesAreMapped() {
        let collector = HealthKitCollector()
        let commonTypes: [UInt: String] = [
            1: "americanFootball", 4: "badminton", 13: "cycling",
            24: "hiking", 37: "running", 46: "swimming",
            52: "walking", 57: "yoga", 63: "highIntensityIntervalTraining"
        ]
        for (rawValue, expectedName) in commonTypes {
            #expect(collector.workoutActivityTypeNames[rawValue] == expectedName,
                    "Type \(rawValue) should be \(expectedName)")
        }
    }
}
