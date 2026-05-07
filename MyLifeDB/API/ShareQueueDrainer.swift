//
//  ShareQueueDrainer.swift
//  MyLifeDB
//
//  Processes shares that the Share Extension staged into the App Group
//  queue (`<App Group>/share-queue/<uuid>/`).
//
//  Two entry points:
//    - `drain(id:)` — called from the `mylifedb://share/<uuid>` deep link
//      when the extension successfully wakes the app.
//    - `drainAll()` — called on app launch and on every foreground so
//      shares whose deeplink handoff failed (or that arrived while the
//      app was offline) eventually upload without manual retry.
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
    /// user having to retry by hand.
    @MainActor
    static func drainAll() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }

        let ids = ShareQueue.listPendingIDs()
        guard !ids.isEmpty else { return }
        print("[ShareQueue] draining \(ids.count) pending share(s)")
        for id in ids {
            await drainInternal(id: id)
        }
    }

    /// Upload one staged share. Public entry point for the deep-link
    /// path; safe to call concurrently with `drainAll()` (the in-flight
    /// guard makes the second caller a no-op rather than a duplicate).
    ///
    /// - Parameter id: Share UUID, parsed from `mylifedb://share/<id>`.
    @MainActor
    static func drain(id: String) async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        await drainInternal(id: id)
    }

    @MainActor
    private static func drainInternal(id: String) async {
        let loaded: ShareQueue.LoadedShare
        do {
            loaded = try ShareQueue.load(id: id)
        } catch {
            print("[ShareQueue] load failed for \(id): \(error.localizedDescription)")
            return
        }

        print("[ShareQueue] draining \(id) with \(loaded.payload.files.count) file(s)")

        var anyFailure = false
        for entry in loaded.payload.files {
            let data: Data
            do {
                data = try loaded.data(for: entry)
            } catch {
                print("[ShareQueue] missing file \(entry.filename) in \(id): \(error.localizedDescription)")
                anyFailure = true
                continue
            }

            do {
                _ = try await APIClient.shared.library.simpleUpload(
                    data: data,
                    filename: entry.filename,
                    destination: "",      // user data root
                    mimeType: entry.mimeType
                )
                print("[ShareQueue] uploaded \(entry.filename) for \(id)")
            } catch {
                print("[ShareQueue] upload failed for \(entry.filename) in \(id): \(error.localizedDescription)")
                anyFailure = true
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
