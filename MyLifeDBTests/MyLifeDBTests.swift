//
//  MyLifeDBTests.swift
//  MyLifeDBTests
//
//  Created by Li Zhao on 2025/12/9.
//

import Testing
import Foundation

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
