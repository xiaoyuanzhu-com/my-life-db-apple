//
//  FileRecord.swift
//  MyLifeDB
//
//  Core file record model matching backend FileRecord.
//

import Foundation

/// Represents a file or folder in the library
struct FileRecord: Codable, Identifiable, Hashable {

    // MARK: - Identifiable

    var id: String { path }

    // MARK: - Properties

    let path: String
    let name: String
    let isFolder: Bool
    let size: Int64?
    let mimeType: String?
    let hash: String?
    let modifiedAt: Int64
    let createdAt: Int64
    let textPreview: String?
    let screenshotSqlar: String?

    // MARK: - Computed Properties

    /// File extension (lowercased)
    var fileExtension: String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// Whether this is an image file
    var isImage: Bool {
        guard let mime = mimeType else { return false }
        return mime.hasPrefix("image/")
    }

    /// Whether this is a video file
    var isVideo: Bool {
        guard let mime = mimeType else { return false }
        return mime.hasPrefix("video/")
    }

    /// Whether this is an audio file
    var isAudio: Bool {
        guard let mime = mimeType else { return false }
        return mime.hasPrefix("audio/")
    }

    /// Whether this is a text file
    var isText: Bool {
        guard let mime = mimeType else { return false }
        return mime.hasPrefix("text/") || mime == "application/json"
    }

    /// Whether this is a PDF file
    var isPDF: Bool {
        mimeType == "application/pdf"
    }

    /// Human-readable file size
    var formattedSize: String? {
        guard let size = size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Parsed modification date
    var modifiedDate: Date { modifiedAt.asDate }

    /// Parsed creation date
    var createdDate: Date { createdAt.asDate }
}

// MARK: - FileRecord + Preview

extension FileRecord {

    /// Whether this file has a screenshot preview
    var hasScreenshot: Bool {
        screenshotSqlar != nil
    }

    /// First line of text preview
    var firstLinePreview: String? {
        guard let preview = textPreview, !preview.isEmpty else { return nil }
        return preview.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
    }
}
