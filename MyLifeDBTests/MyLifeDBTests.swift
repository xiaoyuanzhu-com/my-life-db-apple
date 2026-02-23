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

    @Test func sampleUploadPathShape() {
        let dayString = "2026-02-20"
        let syncTimestamp = "2026-02-20T09-58-48Z"
        let parts = dayString.split(separator: "-")

        // Mirror the exact construction used in HealthKitCollector.collectNewSamples()
        let uploadPath = "imports/fitness/apple-health/\(parts[0])/\(parts[1])/\(parts[2])/sample-\(syncTimestamp).json"

        #expect(uploadPath == "imports/fitness/apple-health/2026/02/20/sample-2026-02-20T09-58-48Z.json")
        #expect(!uploadPath.contains("/raw/"))
        #expect(uploadPath.contains("/sample-"))
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
