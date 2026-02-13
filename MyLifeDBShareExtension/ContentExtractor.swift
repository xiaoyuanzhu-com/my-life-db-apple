//
//  ContentExtractor.swift
//  MyLifeDBShareExtension
//
//  Extracts typed content from NSItemProvider objects provided
//  by the system share sheet. Handles URLs, text, images, and
//  arbitrary files with proper UTType-based MIME detection.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Shared Content Type

/// Represents a piece of shared content ready for upload.
enum SharedContent {
    case url(URL)
    case text(String)
    case fileData(filename: String, data: Data, mimeType: String)
}

// MARK: - Content Extractor

actor ContentExtractor {

    /// Extract all shared content from the extension's input items.
    func extract(from inputItems: [Any]) async -> [SharedContent] {
        var results: [SharedContent] = []

        guard let extensionItems = inputItems as? [NSExtensionItem] else {
            return results
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if let content = await extractContent(from: provider) {
                    results.append(content)
                }
            }
        }

        return results
    }

    // MARK: - Private Extraction

    private func extractContent(from provider: NSItemProvider) async -> SharedContent? {
        // Priority: URL > Text > Image > Any file

        // 1. Try URL (web links from Safari, etc.)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let content = await loadURL(from: provider) {
                return content
            }
        }

        // 2. Try plain text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let content = await loadText(from: provider) {
                return content
            }
        }

        // 3. Try image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let content = await loadImage(from: provider) {
                return content
            }
        }

        // 4. Try any file data as fallback
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            if let content = await loadData(from: provider) {
                return content
            }
        }

        return nil
    }

    // MARK: - URL Loading

    private func loadURL(from provider: NSItemProvider) async -> SharedContent? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)

            if let url = item as? URL {
                // File URLs should be loaded as file data
                if url.isFileURL {
                    return await loadFileURL(url)
                }
                return .url(url)
            }

            // Some apps provide URLs as strings
            if let urlString = item as? String,
               let url = URL(string: urlString),
               let scheme = url.scheme,
               ["http", "https"].contains(scheme.lowercased()) {
                return .url(url)
            }
        } catch {
            // Fall through to other extractors
        }

        return nil
    }

    // MARK: - Text Loading

    private func loadText(from provider: NSItemProvider) async -> SharedContent? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)

            if let text = item as? String, !text.isEmpty {
                // Check if the text is actually a URL
                if let url = URL(string: text),
                   let scheme = url.scheme,
                   ["http", "https"].contains(scheme.lowercased()) {
                    return .url(url)
                }
                return .text(text)
            }
        } catch {
            // Fall through
        }

        return nil
    }

    // MARK: - Image Loading

    private func loadImage(from provider: NSItemProvider) async -> SharedContent? {
        // Try specific image formats in order of preference
        let imageTypes: [(UTType, String, String)] = [
            (.jpeg, "image.jpg", "image/jpeg"),
            (.png, "image.png", "image/png"),
            (.heic, "image.heic", "image/heic"),
            (.gif, "image.gif", "image/gif"),
            (.webP, "image.webp", "image/webp"),
        ]

        for (utType, filename, mimeType) in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(utType.identifier) {
                if let data = await loadDataRepresentation(from: provider, for: utType) {
                    return .fileData(filename: filename, data: data, mimeType: mimeType)
                }
            }
        }

        // Fallback: load as generic image
        if let data = await loadDataRepresentation(from: provider, for: .image) {
            return .fileData(filename: "image.jpg", data: data, mimeType: "image/jpeg")
        }

        return nil
    }

    // MARK: - Generic Data Loading

    private func loadData(from provider: NSItemProvider) async -> SharedContent? {
        let typeIdentifiers = provider.registeredTypeIdentifiers

        for typeID in typeIdentifiers {
            guard let utType = UTType(typeID) else { continue }

            // Skip types we already tried
            if utType.conforms(to: .url) || utType.conforms(to: .plainText) { continue }

            if let data = await loadDataRepresentation(from: provider, for: utType) {
                let suggestedName = provider.suggestedName ?? "file"
                let ext = utType.preferredFilenameExtension ?? ""
                let filename = ext.isEmpty ? suggestedName : (
                    suggestedName.hasSuffix(".\(ext)") ? suggestedName : "\(suggestedName).\(ext)"
                )
                let mime = utType.preferredMIMEType ?? "application/octet-stream"

                return .fileData(filename: filename, data: data, mimeType: mime)
            }
        }

        return nil
    }

    // MARK: - File URL Loading

    private func loadFileURL(_ url: URL) async -> SharedContent? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }

        let filename = url.lastPathComponent
        let mimeType: String
        if let utType = UTType(filenameExtension: url.pathExtension) {
            mimeType = utType.preferredMIMEType ?? "application/octet-stream"
        } else {
            mimeType = "application/octet-stream"
        }

        return .fileData(filename: filename, data: data, mimeType: mimeType)
    }

    // MARK: - Helpers

    private func loadDataRepresentation(from provider: NSItemProvider, for utType: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: utType) { data, error in
                continuation.resume(returning: data)
            }
        }
    }
}
