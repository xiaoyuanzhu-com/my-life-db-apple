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

    /// Deeplink for the most recently staged share, if any. The success
    /// view's "Open MyLifeDB" button uses this to wake the main app
    /// when the user explicitly asks for it.
    private var pendingShareURL: URL?

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

        // The share is on disk; the main app's `drainAll()` will pick
        // it up next time it foregrounds. We don't auto-wake the app
        // here — the user gets to choose on the success screen between
        // staying in the share sheet and jumping into MyLifeDB.
        //
        // The handoff URL is a Universal Link (https), not a custom
        // scheme. iOS routes this to the main app via Associated Domains
        // instead of the deprecated openURL selector path that Apple
        // has progressively locked down on iOS 18+.
        pendingShareURL = URL(string: "https://my.xiaoyuanzhu.com/ios-share/\(shareID)")
        state = .success
    }

    /// Wake the main app to process the share that was just staged.
    /// Used by the success view's "Go to MyLifeDB" button.
    ///
    /// Calls `dismiss` *before* awaiting the open call's completion
    /// handler. iOS tears down the extension's UI when we complete the
    /// extension request, and that teardown was racing the in-flight
    /// `openURL` and silently canceling it. Letting the dismiss happen
    /// first means iOS finishes returning focus to the host app, then
    /// our open request takes effect and brings MyLifeDB to the front.
    func openMainApp(then dismiss: @escaping () -> Void) async {
        guard let url = pendingShareURL, let openHostURL else {
            print("[ShareExt] openMainApp: missing url or opener")
            dismiss()
            return
        }
        print("[ShareExt] openMainApp: scheduling open for \(url)")

        // Fire-and-forget the open so the dismiss can run synchronously.
        Task.detached {
            let opened = await openHostURL(url)
            print("[ShareExt] openMainApp: opener reported success=\(opened)")
        }

        // Give the open request one runloop tick to register before
        // we tear the extension down.
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        dismiss()
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
