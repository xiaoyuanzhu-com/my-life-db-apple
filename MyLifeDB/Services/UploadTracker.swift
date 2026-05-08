//
//  UploadTracker.swift
//  MyLifeDB
//
//  Drives the share-extension upload progress sheet.
//
//  ShareQueueDrainer.drain(id:) calls `begin(...)` to surface a sheet
//  for one share, then forwards per-file progress and terminal state.
//  When every item reaches success/failure the tracker auto-dismisses
//  after a short pause; the user can also swipe down at any time
//  (the upload itself isn't tied to the sheet).
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
#endif

@MainActor
@Observable
final class UploadTracker {

    static let shared = UploadTracker()

    private init() {}

    // MARK: - Types

    enum ItemState: Equatable {
        case pending
        case uploading(Double)
        case success
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .success, .failed: return true
            case .pending, .uploading: return false
            }
        }
    }

    struct Item: Identifiable, Equatable {
        /// Filename within the share — unique per share.
        let id: String
        let filename: String
        let mimeType: String
        let fileURL: URL
        var state: ItemState
        #if canImport(UIKit)
        var thumbnail: UIImage?
        #endif
    }

    struct ShareUpload: Identifiable, Equatable {
        /// Share UUID from the queue folder name.
        let id: String
        var items: [Item]
        let startedAt: Date

        var allFinished: Bool { items.allSatisfy { $0.state.isTerminal } }
    }

    // MARK: - State

    private(set) var activeShare: ShareUpload?

    private var autoDismissTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func begin(id: String, files: [(filename: String, mimeType: String, fileURL: URL)]) {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        let items = files.map { f in
            Item(
                id: f.filename,
                filename: f.filename,
                mimeType: f.mimeType,
                fileURL: f.fileURL,
                state: .pending
            )
        }
        activeShare = ShareUpload(id: id, items: items, startedAt: Date())

        #if canImport(UIKit)
        loadThumbnails(for: id)
        #endif
    }

    func setProgress(itemID: String, _ progress: Double) {
        guard var share = activeShare,
              let idx = share.items.firstIndex(where: { $0.id == itemID }) else { return }
        share.items[idx].state = .uploading(max(0, min(1, progress)))
        activeShare = share
    }

    func setSuccess(itemID: String) {
        guard var share = activeShare,
              let idx = share.items.firstIndex(where: { $0.id == itemID }) else { return }
        share.items[idx].state = .success
        activeShare = share
        scheduleAutoDismissIfDone()
    }

    func setFailure(itemID: String, message: String) {
        guard var share = activeShare,
              let idx = share.items.firstIndex(where: { $0.id == itemID }) else { return }
        share.items[idx].state = .failed(message)
        activeShare = share
        scheduleAutoDismissIfDone()
    }

    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        activeShare = nil
    }

    private func scheduleAutoDismissIfDone() {
        guard let share = activeShare, share.allFinished else { return }
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if let s = self.activeShare, s.allFinished, s.id == share.id {
                    self.activeShare = nil
                }
            }
        }
    }

    // MARK: - Thumbnails

    #if canImport(UIKit)
    private func loadThumbnails(for shareID: String) {
        guard let share = activeShare, share.id == shareID else { return }
        for item in share.items {
            let id = item.id
            let url = item.fileURL
            let mime = item.mimeType
            Task.detached(priority: .userInitiated) {
                let image = Self.makeThumbnail(fileURL: url, mimeType: mime)
                guard let image else { return }
                await MainActor.run {
                    UploadTracker.shared.attachThumbnail(image, itemID: id, shareID: shareID)
                }
            }
        }
    }

    private func attachThumbnail(_ image: UIImage, itemID: String, shareID: String) {
        guard var share = activeShare, share.id == shareID,
              let idx = share.items.firstIndex(where: { $0.id == itemID }) else { return }
        share.items[idx].thumbnail = image
        activeShare = share
    }

    /// Produces a small (~256pt) thumbnail off the main actor. Returns nil for
    /// non-image/video MIMEs or when decoding fails — callers fall back to an
    /// SF Symbol.
    nonisolated private static func makeThumbnail(fileURL: URL, mimeType: String) -> UIImage? {
        if mimeType.hasPrefix("image/") {
            return decodeImageThumbnail(at: fileURL, maxPixel: 512)
        }
        if mimeType.hasPrefix("video/") {
            return decodeVideoThumbnail(at: fileURL, maxPixel: 512)
        }
        return nil
    }

    nonisolated private static func decodeImageThumbnail(at url: URL, maxPixel: Int) -> UIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    nonisolated private static func decodeVideoThumbnail(at url: URL, maxPixel: Int) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }
    #endif
}
