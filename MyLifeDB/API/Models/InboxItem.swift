//
//  InboxItem.swift
//  MyLifeDB
//
//  Inbox item model matching backend InboxItem.
//

import Foundation

/// Represents an inbox item (file awaiting processing)
struct InboxItem: Codable, Identifiable, Hashable {

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
    let digests: [Digest]
    let textPreview: String?
    let screenshotSqlar: String?
    let isPinned: Bool

    // MARK: - Hashable (without digests for simplicity)

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: InboxItem, rhs: InboxItem) -> Bool {
        lhs.path == rhs.path
    }

    // MARK: - Computed Properties

    /// Convert to FileRecord
    var asFileRecord: FileRecord {
        FileRecord(
            path: path,
            name: name,
            isFolder: isFolder,
            size: size,
            mimeType: mimeType,
            hash: hash,
            modifiedAt: modifiedAt,
            createdAt: createdAt,
            textPreview: textPreview,
            screenshotSqlar: screenshotSqlar
        )
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

    /// Human-readable file size
    var formattedSize: String? {
        guard let size = size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// First line of text preview (for display)
    var displayText: String {
        if let preview = textPreview, !preview.isEmpty {
            let firstLine = preview.components(separatedBy: .newlines).first ?? ""
            return firstLine.trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    /// Overall processing status
    var processingStatus: ProcessingStatus {
        if digests.isEmpty {
            return .pending
        }

        let hasProcessing = digests.contains { $0.status == .processing }
        let hasPending = digests.contains { $0.status == .pending || $0.status == .todo }
        let hasFailed = digests.contains { $0.status == .failed }
        let allCompleted = digests.allSatisfy { $0.status == .completed || $0.status == .skipped }

        if hasProcessing {
            return .processing
        } else if allCompleted {
            return .completed
        } else if hasFailed && !hasPending {
            return .failed
        } else {
            return .pending
        }
    }
}

/// Overall processing status for an inbox item
enum ProcessingStatus {
    case pending
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Inbox API Response Types

/// Response from GET /api/inbox
struct InboxResponse: Codable {
    let items: [InboxItem]
    let cursors: InboxCursors
    let hasMore: InboxHasMore
    let targetIndex: Int?
}

/// Cursor information for pagination
struct InboxCursors: Codable {
    let first: String?
    let last: String?
}

/// Pagination info
struct InboxHasMore: Codable {
    let older: Bool
    let newer: Bool
}

/// Response from GET /api/inbox/pinned
struct PinnedInboxResponse: Codable {
    let items: [PinnedItem]
}

/// A pinned inbox item
struct PinnedItem: Codable, Identifiable {
    var id: String { path }

    let path: String
    let name: String
    let pinnedAt: Int64
    let displayText: String
    let cursor: String
}

/// Per-file result in an upload response
struct UploadFileResult: Codable {
    let path: String
    let status: String  // "created" or "skipped"

    var isSkipped: Bool { status == "skipped" }
}

/// Response from POST /api/inbox
struct CreateInboxResponse: Codable {
    let path: String
    let paths: [String]
    let results: [UploadFileResult]?  // nil for older server versions
}

/// Response from GET /api/inbox/:id/status
struct InboxItemStatusResponse: Codable {
    let status: String
    let digests: [Digest]
}
