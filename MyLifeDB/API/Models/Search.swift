//
//  Search.swift
//  MyLifeDB
//
//  Search models for full-text and semantic search.
//

import Foundation

/// A search result item
struct SearchResultItem: Codable, Identifiable {

    // MARK: - Identifiable

    var id: String { path }

    // MARK: - Properties

    let path: String
    let name: String
    let isFolder: Bool
    let size: Int64?
    let mimeType: String?
    let modifiedAt: String
    let createdAt: String
    let digests: [Digest]
    let score: Double
    let snippet: String
    let textPreview: String?
    let screenshotSqlar: String?
    let highlights: [String: String]?
    let matchContext: MatchContext?
    let matchedObject: MatchedObject?

    // MARK: - Computed Properties

    /// Whether this is an image file
    var isImage: Bool {
        guard let mime = mimeType else { return false }
        return mime.hasPrefix("image/")
    }

    /// Human-readable file size
    var formattedSize: String? {
        guard let size = size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Display text (snippet or filename)
    var displayText: String {
        if !snippet.isEmpty {
            return snippet
        }
        return name
    }
}

/// Context about where the match was found
struct MatchContext: Codable {
    let source: String // "digest" or "semantic"
    let snippet: String
    let terms: [String]
    let score: Double?
    let sourceType: String?
    let digest: DigestInfo?

    struct DigestInfo: Codable {
        let type: String
        let label: String
    }
}

/// A matched object from image-objects digest
struct MatchedObject: Codable {
    let title: String
    let bbox: [Double]
    let rle: RleMask?
}

/// RLE mask for segmentation
struct RleMask: Codable {
    let size: [Int]
    let counts: [Int]
}

// MARK: - Search Response

/// Response from GET /api/search
struct SearchResponse: Codable {
    let results: [SearchResultItem]
    let pagination: SearchPagination
    let query: String
    let timing: SearchTiming
    let sources: [String]
}

/// Search pagination info
struct SearchPagination: Codable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

/// Search timing information
struct SearchTiming: Codable {
    let totalMs: Int64
    let searchMs: Int64
    let enrichMs: Int64
}
