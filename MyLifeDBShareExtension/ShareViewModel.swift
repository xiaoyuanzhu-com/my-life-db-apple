//
//  ShareViewModel.swift
//  MyLifeDBShareExtension
//
//  State management for the Share Extension compose view.
//  Handles content extraction, preview generation, and upload.
//

import Foundation
import Observation

@Observable
final class ShareViewModel {

    // MARK: - State

    enum State: Equatable {
        case loading
        case ready
        case uploading
        case success
        case error(String)
        case notAuthenticated

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading),
                 (.ready, .ready),
                 (.uploading, .uploading),
                 (.success, .success),
                 (.notAuthenticated, .notAuthenticated):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: State = .loading

    /// User-provided note to include with the shared content.
    var userNote: String = ""

    // MARK: - Extracted Content

    private(set) var items: [SharedContent] = []

    private let apiClient = SharedAPIClient()
    private let extractor = ContentExtractor()

    // MARK: - Computed Properties

    var hasContent: Bool {
        !items.isEmpty
    }

    // MARK: - Content Extraction

    func extractContent(from inputItems: [Any]) async {
        // Check auth first
        guard SharedKeychainHelper.loadAccessToken() != nil else {
            state = .notAuthenticated
            return
        }

        state = .loading
        items = await extractor.extract(from: inputItems)

        if hasContent {
            state = .ready
        } else {
            state = .error("No shareable content found.")
        }
    }

    // MARK: - Upload

    func upload() async {
        state = .uploading

        // Build the text payload
        var textParts: [String] = []

        // User note first
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            textParts.append(trimmedNote)
        }

        // Collect URLs and text from items
        var files: [(filename: String, data: Data, mimeType: String)] = []

        for item in items {
            switch item.kind {
            case .url(let url):
                textParts.append(url.absoluteString)
            case .text(let text):
                textParts.append(text)
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

        let combinedText = textParts.isEmpty ? nil : textParts.joined(separator: "\n\n")

        do {
            try await apiClient.uploadToInbox(
                text: combinedText,
                files: files
            )
            state = .success
        } catch let error as ShareUploadError {
            if case .notAuthenticated = error {
                state = .notAuthenticated
            } else {
                state = .error(error.localizedDescription)
            }
        } catch {
            state = .error("Upload failed: \(error.localizedDescription)")
        }
    }
}
