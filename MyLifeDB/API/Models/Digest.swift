//
//  Digest.swift
//  MyLifeDB
//
//  Digest model for file processing results.
//

import Foundation

/// Status of a digest processing job
enum DigestStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
    case skipped
    case todo
}

/// Represents a processed digest for a file
struct Digest: Codable, Identifiable {

    // MARK: - Properties

    let id: String
    let filePath: String
    let digester: String
    let status: DigestStatus
    let content: String?
    let sqlarName: String?
    let error: String?
    let attempts: Int
    let createdAt: Int64
    let updatedAt: Int64

    // MARK: - Computed Properties

    /// Whether the digest completed successfully
    var isCompleted: Bool {
        status == .completed
    }

    /// Whether the digest failed
    var isFailed: Bool {
        status == .failed
    }

    /// Whether the digest is still processing
    var isProcessing: Bool {
        status == .processing || status == .pending || status == .todo
    }

    /// Human-readable digester name
    var digesterDisplayName: String {
        switch digester {
        case "summary":
            return "Summary"
        case "tags":
            return "Tags"
        case "screenshot":
            return "Screenshot"
        case "text":
            return "Text Extraction"
        case "transcript":
            return "Transcript"
        case "ocr":
            return "OCR"
        case "image-objects":
            return "Object Detection"
        default:
            return digester.capitalized
        }
    }
}

// MARK: - Digester Info

/// Information about a registered digester
struct DigesterInfo: Codable, Identifiable {
    var id: String { name }

    let name: String
    let mimeTypes: [String]
    let description: String?
}

/// Response from GET /api/digest/digesters
struct DigestersResponse: Codable {
    let digesters: [DigesterInfo]
}

/// Response from GET /api/digest/stats
struct DigestStatsResponse: Codable {
    let total: Int
    let byStatus: [String: Int]
    let byDigester: [String: Int]
}
