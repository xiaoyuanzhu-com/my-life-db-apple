//
//  SyncWatermarkTests.swift
//  MyLifeDBTests
//
//  Tests for SHA-256 watermark manager used to skip unchanged uploads.
//

import Testing
import Foundation
@testable import MyLifeDB

struct SyncWatermarkTests {

    @Test func newFileHasNoWatermark() {
        let wm = SyncWatermark(store: MockDefaults())
        #expect(wm.hasChanged(path: "2026/02/09/step-count.json", data: Data("hello".utf8)))
    }

    @Test func unchangedFileIsSkipped() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)
        let data = Data("same content".utf8)

        #expect(wm.hasChanged(path: "a.json", data: data))
        wm.recordUpload(path: "a.json", data: data)
        #expect(!wm.hasChanged(path: "a.json", data: data))
    }

    @Test func changedFileIsDetected() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)

        let data1 = Data("v1".utf8)
        let data2 = Data("v2".utf8)

        wm.recordUpload(path: "a.json", data: data1)
        #expect(wm.hasChanged(path: "a.json", data: data2))
    }

    @Test func clearRemovesAll() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)

        wm.recordUpload(path: "a.json", data: Data("x".utf8))
        wm.clearAll()
        #expect(wm.hasChanged(path: "a.json", data: Data("x".utf8)))
    }

    @Test func differentPathsAreIndependent() {
        let store = MockDefaults()
        let wm = SyncWatermark(store: store)
        let data = Data("same".utf8)

        wm.recordUpload(path: "a.json", data: data)
        #expect(wm.hasChanged(path: "b.json", data: data), "Different path should not match")
    }
}

/// In-memory mock for UserDefaults
final class MockDefaults: SyncWatermarkStore {
    private var dict: [String: String] = [:]

    func string(forKey key: String) -> String? { dict[key] }
    func set(_ value: String?, forKey key: String) {
        if let value { dict[key] = value } else { dict[key] = nil }
    }
    func removeAll(prefix: String) {
        dict = dict.filter { !$0.key.hasPrefix(prefix) }
    }
}
