//
//  ShareQueueDrainer.swift
//  MyLifeDB
//
//  Processes shares that the Share Extension staged into the App Group
//  queue (`<App Group>/share-queue/<uuid>/`).
//
//  Two entry points:
//    - `drain(id:)` — called from the universal-link handoff
//      (`https://my.xiaoyuanzhu.com/ios-share/<uuid>`). Surfaces the
//      `UploadTracker` sheet so the user sees per-file progress.
//    - `drainAll()` — called on app launch and on every foreground so
//      shares whose deeplink handoff failed (or that arrived while the
//      app was offline) eventually upload without manual retry. Stays
//      silent — the user didn't ask for a sheet.
//
//  Per-share semantics: each share folder is uploaded as one atomic
//  unit. On any upload failure, the folder stays on disk and will be
//  retried on the next drain pass. On full success the folder is
//  removed. Shares are independent — failing share A does not block
//  share B from uploading.
//

import Foundation

enum ShareQueueDrainer {

    /// In-flight guard so simultaneous foreground + deeplink triggers
    /// don't race each other on the same folders. Reads/writes are
    /// safe because both entry points are reached from the main actor.
    @MainActor private static var draining = false

    /// Drain every staged share. Called on app launch / foreground so
    /// shares that arrived while the app was backgrounded (or while the
    /// extension's `open(_:)` handoff failed) are uploaded without the
    /// user having to retry by hand. Silent — no UI sheet.
    @MainActor
    static func drainAll() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        let ids = ShareQueue.listPendingIDs()
        guard !ids.isEmpty else { return }
        print("[ShareQueue] draining \(ids.count) pending share(s)")
        for id in ids {
            await drainInternal(id: id, silent: true)
        }
    }

    /// Upload one staged share and surface progress in the upload sheet.
    /// Public entry point for the universal-link handoff path; safe to
    /// call concurrently with `drainAll()` (the in-flight guard makes
    /// the second caller a no-op rather than a duplicate).
    ///
    /// - Parameter id: Share UUID, parsed from
    ///   `https://my.xiaoyuanzhu.com/ios-share/<id>`.
    @MainActor
    static func drain(id: String) async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        await drainInternal(id: id, silent: false)
    }

    @MainActor
    private static func drainInternal(id: String, silent: Bool) async {
        let loaded: ShareQueue.LoadedShare
        do {
            loaded = try ShareQueue.load(id: id)
        } catch {
            print("[ShareQueue] load failed for \(id): \(error.localizedDescription)")
            return
        }

        print("[ShareQueue] draining \(id) with \(loaded.payload.files.count) file(s)")

        if !silent {
            let files = loaded.payload.files.map { entry in
                (filename: entry.filename, mimeType: entry.mimeType, fileURL: loaded.fileURL(for: entry))
            }
            UploadTracker.shared.begin(id: id, files: files)
        }

        var anyFailure = false
        for entry in loaded.payload.files {
            let fileURL = loaded.fileURL(for: entry)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[ShareQueue] missing file \(entry.filename) in \(id)")
                anyFailure = true
                if !silent {
                    UploadTracker.shared.setFailure(itemID: entry.filename, message: "File missing")
                }
                continue
            }

            if !silent {
                UploadTracker.shared.setProgress(itemID: entry.filename, 0)
            }

            do {
                let filename = entry.filename
                let progressCallback: (@Sendable (Double) -> Void)?
                if silent {
                    progressCallback = nil
                } else {
                    progressCallback = { progress in
                        Task<Void, Never> { @MainActor in
                            UploadTracker.shared.setProgress(itemID: filename, progress)
                        }
                    }
                }
                _ = try await APIClient.shared.library.simpleUploadFromFile(
                    fileURL: fileURL,
                    filename: filename,
                    destination: "",      // user data root
                    mimeType: entry.mimeType,
                    onProgress: progressCallback
                )
                print("[ShareQueue] uploaded \(entry.filename) for \(id)")
                if !silent {
                    UploadTracker.shared.setSuccess(itemID: entry.filename)
                }
            } catch {
                print("[ShareQueue] upload failed for \(entry.filename) in \(id): \(error.localizedDescription)")
                anyFailure = true
                if !silent {
                    UploadTracker.shared.setFailure(itemID: entry.filename, message: error.localizedDescription)
                }
            }
        }

        if anyFailure {
            // Keep the folder so the next drain pass retries it.
            print("[ShareQueue] \(id) had failures; leaving folder on disk")
        } else {
            ShareQueue.remove(id: id)
            print("[ShareQueue] \(id) drained and removed")
        }
    }
}
