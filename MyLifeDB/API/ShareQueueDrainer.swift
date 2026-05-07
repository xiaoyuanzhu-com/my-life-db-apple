//
//  ShareQueueDrainer.swift
//  MyLifeDB
//
//  Processes a single share that the Share Extension staged into the
//  App Group queue (`<App Group>/share-queue/<uuid>/`).
//
//  Per-share isolation: this drainer only ever touches the share named
//  in the deep-link URL. Previous failed shares are left untouched —
//  they will be processed only when their own deep link is followed,
//  or cleaned up manually. This avoids surprise re-uploads of stale
//  content.
//

import Foundation

enum ShareQueueDrainer {

    /// Upload one staged share to the user data root, then remove it.
    ///
    /// - Parameter id: Share UUID, parsed from `mylifedb://share/<id>`.
    static func drain(id: String) async {
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
            // Leave the share folder on disk so it can be retried by
            // re-following the same deep link or by a future "pending
            // shares" UI. Never sweep up other shares.
            print("[ShareQueue] \(id) had failures; leaving folder on disk")
        } else {
            ShareQueue.remove(id: id)
            print("[ShareQueue] \(id) drained and removed")
        }
    }
}
