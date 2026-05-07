//
//  ShareViewModel.swift
//  MyLifeDBShareExtension
//
//  State management for the Share Extension compose view.
//
//  The extension does not upload directly. Each "Send" stages a new
//  share folder (UUID-named) into the App Group container, then opens
//  `mylifedb://share/<uuid>` so the main app — which already owns auth,
//  token refresh, and the API client — performs the actual upload.
//

import Foundation
import Observation

@Observable
final class ShareViewModel {

    // MARK: - State

    enum State: Equatable {
        case loading
        case ready
        case staging
        case success
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading),
                 (.ready, .ready),
                 (.staging, .staging),
                 (.success, .success):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: State = .loading

    // MARK: - Extracted Content

    private(set) var items: [SharedContent] = []

    private let extractor = ContentExtractor()

    /// Closure provided by ShareViewController. Asks the extension's
    /// host context to open a URL (i.e., wake the main app). Returns
    /// whether the OS reported a successful open.
    var openHostURL: ((URL) async -> Bool)?

    // MARK: - Computed Properties

    var hasContent: Bool {
        !items.isEmpty
    }

    // MARK: - Content Extraction

    func extractContent(from inputItems: [Any]) async {
        state = .loading
        items = await extractor.extract(from: inputItems)

        if hasContent {
            state = .ready
        } else {
            state = .error(String(localized: "No shareable content found."))
        }
    }

    // MARK: - Send (stage + handoff)

    func send() async {
        state = .staging

        // Convert all shared items into a uniform list of file payloads.
        // URL/text shares become auto-named .txt files so the main app's
        // upload path stays purely file-oriented.
        var files: [(filename: String, data: Data, mimeType: String)] = []

        for item in items {
            switch item.kind {
            case .url(let url):
                if let data = url.absoluteString.data(using: .utf8) {
                    files.append((
                        filename: makeAutoFilename(prefix: "link", ext: "txt"),
                        data: data,
                        mimeType: "text/plain"
                    ))
                }
            case .text(let text):
                if let data = text.data(using: .utf8) {
                    files.append((
                        filename: makeAutoFilename(prefix: "text", ext: "txt"),
                        data: data,
                        mimeType: "text/plain"
                    ))
                }
            case .imageFile(let filename, let data, let mimeType, _):
                files.append((filename: filename, data: data, mimeType: mimeType))
            case .videoFile(let filename, let data, let mimeType, _):
                files.append((filename: filename, data: data, mimeType: mimeType))
            case .audioFile(let filename, let data, let mimeType):
                files.append((filename: filename, data: data, mimeType: mimeType))
            case .genericFile(let filename, let data, let mimeType, _):
                files.append((filename: filename, data: data, mimeType: mimeType))
            }
        }

        guard !files.isEmpty else {
            state = .error("Nothing to send.")
            return
        }

        // Stage to the App Group queue.
        let shareID: String
        do {
            shareID = try ShareQueue.enqueue(files: files)
        } catch {
            state = .error("Failed to stage share: \(error.localizedDescription)")
            return
        }

        // Hand off to the main app.
        guard var components = URLComponents(string: "mylifedb://share") else {
            state = .error("Invalid share URL.")
            return
        }
        components.path = "/\(shareID)"
        guard let url = components.url else {
            state = .error("Invalid share URL.")
            return
        }

        guard let openHostURL else {
            // No host context available — share is staged on disk and
            // will be processed next time the user opens the app.
            state = .success
            return
        }

        let opened = await openHostURL(url)
        if opened {
            state = .success
        } else {
            // Couldn't wake the app; the staged share remains on disk
            // so opening MyLifeDB later will still finish the job.
            state = .error("Couldn't open MyLifeDB. Open the app to finish sending.")
        }
    }

    // MARK: - Helpers

    /// Build a timestamped filename like `link-2026-05-06-143052.txt`.
    private func makeAutoFilename(prefix: String, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(prefix)-\(formatter.string(from: Date())).\(ext)"
    }
}
