//
//  ShareQueue.swift
//  Shared between MyLifeDB app and Share Extension
//
//  Per-share file queue backed by the App Group container.
//
//  Each share is its own folder identified by a UUID:
//
//      <App Group container>/share-queue/<uuid>/
//          manifest.json         — files + metadata
//          <filename-1>          — raw bytes
//          <filename-2>
//          ...
//
//  The Share Extension calls `enqueue` to stage files, then opens
//  `mylifedb://share/<uuid>` to hand the work to the main app, which
//  uses `load` + `remove` to upload and clean up.
//
//  Independence: each share is self-contained. The main app processes
//  exactly the share named in the deep link — it never sweeps up other
//  pending or failed shares behind the user's back.
//

import Foundation

// MARK: - Manifest

struct SharePayload: Codable {
    let id: String
    let createdAt: Date
    let files: [FileEntry]

    struct FileEntry: Codable {
        /// Filename inside the share folder (matches the on-disk name).
        let filename: String
        /// MIME type to send in Content-Type when uploading.
        let mimeType: String
    }
}

// MARK: - Errors

enum ShareQueueError: LocalizedError {
    case noContainer
    case manifestMissing(String)
    case fileMissing(String)
    case ioError(Error)

    var errorDescription: String? {
        switch self {
        case .noContainer:
            return "App Group container not available."
        case .manifestMissing(let id):
            return "Share \(id) has no manifest."
        case .fileMissing(let name):
            return "Share file missing: \(name)"
        case .ioError(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Queue

enum ShareQueue {

    private static let queueFolderName = "share-queue"
    private static let manifestName = "manifest.json"

    /// Root of the share queue inside the App Group container.
    /// Created on demand.
    private static func queueRoot() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConstants.appGroupID
        ) else {
            throw ShareQueueError.noContainer
        }
        let root = container.appendingPathComponent(queueFolderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }
        return root
    }

    /// Path to the folder for a specific share ID.
    static func folder(for id: String) throws -> URL {
        try queueRoot().appendingPathComponent(id, isDirectory: true)
    }

    // MARK: - Enqueue (called by extension)

    /// Stage a new share to disk. Returns the generated share ID.
    static func enqueue(
        files: [(filename: String, data: Data, mimeType: String)]
    ) throws -> String {
        let id = UUID().uuidString
        let folder = try Self.folder(for: id)

        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        } catch {
            throw ShareQueueError.ioError(error)
        }

        var entries: [SharePayload.FileEntry] = []
        for file in files {
            let dest = folder.appendingPathComponent(file.filename)
            do {
                try file.data.write(to: dest, options: .atomic)
            } catch {
                throw ShareQueueError.ioError(error)
            }
            entries.append(.init(filename: file.filename, mimeType: file.mimeType))
        }

        let manifest = SharePayload(id: id, createdAt: Date(), files: entries)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(
                to: folder.appendingPathComponent(manifestName),
                options: .atomic
            )
        } catch {
            throw ShareQueueError.ioError(error)
        }

        return id
    }

    // MARK: - Load + Remove (called by main app)

    /// Result of loading a share: the manifest plus an iterator of file
    /// payloads on disk.
    struct LoadedShare {
        let payload: SharePayload
        let folder: URL

        /// Read the bytes for a file entry.
        func data(for entry: SharePayload.FileEntry) throws -> Data {
            let url = folder.appendingPathComponent(entry.filename)
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ShareQueueError.fileMissing(entry.filename)
            }
        }
    }

    /// Load a share by ID. Throws if the share folder or manifest is missing.
    static func load(id: String) throws -> LoadedShare {
        let folder = try Self.folder(for: id)
        let manifestURL = folder.appendingPathComponent(manifestName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ShareQueueError.manifestMissing(id)
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(SharePayload.self, from: data)
            return LoadedShare(payload: payload, folder: folder)
        } catch {
            throw ShareQueueError.ioError(error)
        }
    }

    /// Delete a share folder. Best-effort; ignores errors so cleanup never
    /// blocks a successful upload from being reported back to the user.
    static func remove(id: String) {
        guard let folder = try? Self.folder(for: id) else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
