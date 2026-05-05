//
//  LibraryTreeCache.swift
//  MyLifeDB
//
//  Persisted snapshot cache for /api/data/tree responses, keyed by folder path.
//
//  Purpose: eliminate the launch-time spinner in LibraryFolderView. On a warm
//  start, the last-known folder contents are loaded synchronously from disk
//  and rendered immediately while a background refresh fetches the latest
//  tree. The UI only updates if the new response differs from the snapshot.
//
//  Storage: JSON file per path under Caches/library-tree/. Caches/ is fine —
//  the data is recoverable from the server, so the OS may evict under
//  storage pressure with no data loss.
//

import Foundation
import CryptoKit

final class LibraryTreeCache: @unchecked Sendable {

    static let shared = LibraryTreeCache()

    // MARK: - Storage

    private let queue = DispatchQueue(label: "mylifedb.library-tree-cache", attributes: .concurrent)
    private var memory: [String: FileTreeResponse] = [:]
    private let diskDir: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Init

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskDir = caches.appendingPathComponent("library-tree", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Synchronously returns the last cached snapshot for `path`, or nil.
    /// Reads from memory first; falls back to disk on a miss.
    func snapshot(for path: String) -> FileTreeResponse? {
        let key = cacheKey(path)

        if let cached = queue.sync(execute: { memory[key] }) {
            return cached
        }

        let fileURL = diskDir.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(FileTreeResponse.self, from: data) else {
            return nil
        }

        queue.async(flags: .barrier) { [weak self] in
            self?.memory[key] = decoded
        }
        return decoded
    }

    /// Persist a snapshot for `path`. Writes are async; the in-memory layer
    /// is updated synchronously so subsequent `snapshot(for:)` calls see it.
    func save(_ response: FileTreeResponse, for path: String) {
        let key = cacheKey(path)
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.memory[key] = response
            let fileURL = self.diskDir.appendingPathComponent(key + ".json")
            if let data = try? self.encoder.encode(response) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Remove all cached snapshots (memory + disk). Used on logout.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.memory.removeAll()
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: self.diskDir, includingPropertiesForKeys: nil
            ) {
                for url in entries { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    // MARK: - Helpers

    /// Hashed filename so paths with `/`, special chars, or arbitrary length
    /// map to a safe single-segment file name.
    private func cacheKey(_ path: String) -> String {
        let canonical = path.isEmpty ? "__root__" : path
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
