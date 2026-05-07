//
//  ContentExtractor.swift
//  MyLifeDBShareExtension
//
//  Extracts typed content from NSItemProvider objects provided
//  by the system share sheet. Handles URLs, text, images, videos,
//  audio, and arbitrary files with proper UTType-based detection
//  and thumbnail generation for rich previews.
//

import AVFoundation
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

// MARK: - Shared Content Type

struct SharedContent: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case url(URL)
        case text(String)
        case imageFile(filename: String, data: Data, mimeType: String, thumbnail: UIImage)
        case videoFile(filename: String, data: Data, mimeType: String, thumbnail: UIImage?)
        case audioFile(filename: String, data: Data, mimeType: String)
        case genericFile(filename: String, data: Data, mimeType: String, utType: UTType?)
    }
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
        // Priority: URL > Text > Image > Video > Audio > Any file

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

        // 4. Try video
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
           provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) {
            if let content = await loadVideo(from: provider) {
                return content
            }
        }

        // 5. Try audio
        if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            if let content = await loadAudio(from: provider) {
                return content
            }
        }

        // 6. Try any file data as fallback
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
                return SharedContent(kind: .url(url))
            }

            // Some apps provide URLs as strings
            if let urlString = item as? String,
               let url = URL(string: urlString),
               let scheme = url.scheme,
               ["http", "https"].contains(scheme.lowercased()) {
                return SharedContent(kind: .url(url))
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
                    return SharedContent(kind: .url(url))
                }
                return SharedContent(kind: .text(text))
            }
        } catch {
            // Fall through
        }

        return nil
    }

    // MARK: - Image Loading

    private func loadImage(from provider: NSItemProvider) async -> SharedContent? {
        // Try specific image formats in order of preference.
        let imageTypes: [(UTType, String)] = [
            (.jpeg, "image/jpeg"),
            (.png, "image/png"),
            (.heic, "image/heic"),
            (.gif, "image/gif"),
            (.webP, "image/webp"),
        ]

        for (utType, mimeType) in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(utType.identifier) {
                if let data = await loadDataRepresentation(from: provider, for: utType) {
                    let thumbnail = createThumbnail(from: data, maxDimension: 600)
                    if let thumbnail {
                        let filename = makeFilename(
                            suggested: provider.suggestedName,
                            prefix: "photo",
                            ext: utType.preferredFilenameExtension ?? "jpg"
                        )
                        return SharedContent(kind: .imageFile(
                            filename: filename,
                            data: data,
                            mimeType: mimeType,
                            thumbnail: thumbnail
                        ))
                    }
                }
            }
        }

        // Fallback: load as generic image
        if let data = await loadDataRepresentation(from: provider, for: .image) {
            let thumbnail = createThumbnail(from: data, maxDimension: 600) ?? UIImage(systemName: "photo")!
            let filename = makeFilename(
                suggested: provider.suggestedName,
                prefix: "photo",
                ext: "jpg"
            )
            return SharedContent(kind: .imageFile(
                filename: filename,
                data: data,
                mimeType: "image/jpeg",
                thumbnail: thumbnail
            ))
        }

        return nil
    }

    // MARK: - Video Loading

    private func loadVideo(from provider: NSItemProvider) async -> SharedContent? {
        let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie, .video]

        for utType in videoTypes {
            if provider.hasItemConformingToTypeIdentifier(utType.identifier) {
                if let data = await loadDataRepresentation(from: provider, for: utType) {
                    let filename = makeFilename(
                        suggested: provider.suggestedName,
                        prefix: "video",
                        ext: utType.preferredFilenameExtension ?? "mp4"
                    )
                    let mime = utType.preferredMIMEType ?? "video/mp4"

                    let thumbnail = await generateVideoThumbnail(from: data)

                    return SharedContent(kind: .videoFile(
                        filename: filename,
                        data: data,
                        mimeType: mime,
                        thumbnail: thumbnail
                    ))
                }
            }
        }

        return nil
    }

    // MARK: - Audio Loading

    private func loadAudio(from provider: NSItemProvider) async -> SharedContent? {
        let audioTypes: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]

        for utType in audioTypes {
            if provider.hasItemConformingToTypeIdentifier(utType.identifier) {
                if let data = await loadDataRepresentation(from: provider, for: utType) {
                    let filename = makeFilename(
                        suggested: provider.suggestedName,
                        prefix: "audio",
                        ext: utType.preferredFilenameExtension ?? "m4a"
                    )
                    let mime = utType.preferredMIMEType ?? "audio/mpeg"

                    return SharedContent(kind: .audioFile(
                        filename: filename,
                        data: data,
                        mimeType: mime
                    ))
                }
            }
        }

        return nil
    }

    // MARK: - Generic Data Loading

    private func loadData(from provider: NSItemProvider) async -> SharedContent? {
        let typeIdentifiers = provider.registeredTypeIdentifiers

        for typeID in typeIdentifiers {
            guard let utType = UTType(typeID) else { continue }

            // Skip types we already tried
            if utType.conforms(to: .url) || utType.conforms(to: .plainText) ||
               utType.conforms(to: .image) || utType.conforms(to: .movie) ||
               utType.conforms(to: .video) || utType.conforms(to: .audio) { continue }

            if let data = await loadDataRepresentation(from: provider, for: utType) {
                let filename = makeFilename(
                    suggested: provider.suggestedName,
                    prefix: "file",
                    ext: utType.preferredFilenameExtension ?? ""
                )
                let mime = utType.preferredMIMEType ?? "application/octet-stream"

                return SharedContent(kind: .genericFile(
                    filename: filename,
                    data: data,
                    mimeType: mime,
                    utType: utType
                ))
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
        let utType = UTType(filenameExtension: url.pathExtension)
        let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"

        // Route to specific type based on UTType
        if let utType, utType.conforms(to: .image) {
            let thumbnail = createThumbnail(from: data, maxDimension: 600) ?? UIImage(systemName: "photo")!
            return SharedContent(kind: .imageFile(filename: filename, data: data, mimeType: mimeType, thumbnail: thumbnail))
        }

        if let utType, utType.conforms(to: .movie) || utType.conforms(to: .video) {
            let thumbnail = await generateVideoThumbnail(from: data)
            return SharedContent(kind: .videoFile(filename: filename, data: data, mimeType: mimeType, thumbnail: thumbnail))
        }

        if let utType, utType.conforms(to: .audio) {
            return SharedContent(kind: .audioFile(filename: filename, data: data, mimeType: mimeType))
        }

        return SharedContent(kind: .genericFile(filename: filename, data: data, mimeType: mimeType, utType: utType))
    }

    // MARK: - Thumbnail Generation

    /// Create a downsampled thumbnail from image data using ImageIO for memory efficiency.
    private func createThumbnail(from data: Data, maxDimension: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Generate a thumbnail from video data using AVAssetImageGenerator.
    private func generateVideoThumbnail(from data: Data) async -> UIImage? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        do {
            try data.write(to: tempURL)
        } catch {
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func loadDataRepresentation(from provider: NSItemProvider, for utType: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: utType) { data, error in
                continuation.resume(returning: data)
            }
        }
    }

    /// Decide the filename to use for a shared item.
    ///
    /// When the item provider gives us a `suggestedName` (e.g. from the
    /// Files app, Mail attachments, or screenshots), keep it — it carries
    /// real user intent. Apple Photos historically does **not** expose
    /// the original asset filename through `NSItemProvider.suggestedName`
    /// for privacy reasons, so we fall back to a timestamped name like
    /// `photo-2026-05-07-143052.jpg` rather than a generic `image.jpg`
    /// that would collide on every share.
    ///
    /// - Parameters:
    ///   - suggested: `provider.suggestedName`. May be nil or empty.
    ///   - prefix: Type-specific prefix used when no suggested name is
    ///     available (e.g. `"photo"`, `"video"`, `"audio"`, `"file"`).
    ///   - ext: Lowercase file extension (no leading dot). May be empty
    ///     for unknown types.
    private func makeFilename(suggested: String?, prefix: String, ext: String) -> String {
        let trimmed = suggested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return appendExtensionIfNeeded(trimmed, ext: ext)
        }
        let stem = "\(prefix)-\(timestampString())"
        return appendExtensionIfNeeded(stem, ext: ext)
    }

    /// Add `.<ext>` to `name` unless the extension is empty or already
    /// matches (case-insensitive).
    private func appendExtensionIfNeeded(_ name: String, ext: String) -> String {
        guard !ext.isEmpty else { return name }
        let currentExt = (name as NSString).pathExtension.lowercased()
        if currentExt == ext.lowercased() { return name }
        return "\(name).\(ext)"
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
