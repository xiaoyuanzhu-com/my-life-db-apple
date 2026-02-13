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

    private(set) var extractedURLs: [URL] = []
    private(set) var extractedTexts: [String] = []
    private(set) var extractedFiles: [(filename: String, data: Data, mimeType: String)] = []

    private let apiClient = SharedAPIClient()
    private let extractor = ContentExtractor()

    // MARK: - Computed Properties

    /// Preview text shown in the compose view.
    var contentPreview: String {
        var parts: [String] = []

        for url in extractedURLs {
            parts.append(url.absoluteString)
        }
        for text in extractedTexts {
            let preview = String(text.prefix(200))
            parts.append(preview)
        }
        for file in extractedFiles {
            let sizeStr = ByteCountFormatter.string(
                fromByteCount: Int64(file.data.count),
                countStyle: .file
            )
            parts.append("\(file.filename) (\(sizeStr))")
        }

        return parts.joined(separator: "\n")
    }

    var hasContent: Bool {
        !extractedURLs.isEmpty || !extractedTexts.isEmpty || !extractedFiles.isEmpty
    }

    // MARK: - Content Extraction

    func extractContent(from inputItems: [Any]) async {
        // Check auth first
        guard SharedKeychainHelper.loadAccessToken() != nil else {
            state = .notAuthenticated
            return
        }

        state = .loading
        let contents = await extractor.extract(from: inputItems)

        for content in contents {
            switch content {
            case .url(let url):
                extractedURLs.append(url)
            case .text(let text):
                extractedTexts.append(text)
            case .fileData(let filename, let data, let mimeType):
                extractedFiles.append((filename: filename, data: data, mimeType: mimeType))
            }
        }

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

        // URLs
        for url in extractedURLs {
            textParts.append(url.absoluteString)
        }

        // Extracted text
        for text in extractedTexts {
            textParts.append(text)
        }

        let combinedText = textParts.isEmpty ? nil : textParts.joined(separator: "\n\n")

        do {
            try await apiClient.uploadToInbox(
                text: combinedText,
                files: extractedFiles
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
