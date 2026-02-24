//
//  SyncWatermark.swift
//  MyLifeDB
//
//  SHA-256 watermark manager: tracks the last-uploaded hash of each file
//  path so unchanged files can be skipped during sync.
//

import Foundation
import CryptoKit

protocol SyncWatermarkStore {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func removeAll(prefix: String)
}

extension UserDefaults: SyncWatermarkStore {
    func set(_ value: String?, forKey key: String) {
        if let value {
            set(value as NSString, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }

    func removeAll(prefix: String) {
        for key in dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            removeObject(forKey: key)
        }
    }
}

final class SyncWatermark {
    private let store: SyncWatermarkStore
    private static let keyPrefix = "sync.watermark."

    init(store: SyncWatermarkStore = UserDefaults.standard) {
        self.store = store
    }

    func hasChanged(path: String, data: Data) -> Bool {
        let newHash = sha256(data)
        let oldHash = store.string(forKey: Self.keyPrefix + path)
        return newHash != oldHash
    }

    func recordUpload(path: String, data: Data) {
        store.set(sha256(data), forKey: Self.keyPrefix + path)
    }

    func clearAll() {
        store.removeAll(prefix: Self.keyPrefix)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
