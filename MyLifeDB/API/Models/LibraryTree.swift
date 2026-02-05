//
//  LibraryTree.swift
//  MyLifeDB
//
//  Library tree structure models.
//

import Foundation

/// A node in the library tree (file or folder)
struct LibraryNode: Codable, Identifiable, Hashable {

    // MARK: - Identifiable

    var id: String { path }

    // MARK: - Properties

    let path: String
    let name: String
    let isFolder: Bool
    let size: Int64?
    let mimeType: String?
    let modifiedAt: String?
    let createdAt: String?
    let children: [LibraryNode]?

    // MARK: - Computed Properties

    /// Whether this node has children
    var hasChildren: Bool {
        guard let children = children else { return false }
        return !children.isEmpty
    }

    /// Number of children
    var childCount: Int {
        children?.count ?? 0
    }

    /// File extension
    var fileExtension: String? {
        guard !isFolder else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// SF Symbol name for this node type
    var systemImage: String {
        if isFolder {
            return "folder.fill"
        }

        switch mimeType {
        case let mime where mime?.hasPrefix("image/") == true:
            return "photo"
        case let mime where mime?.hasPrefix("video/") == true:
            return "video"
        case let mime where mime?.hasPrefix("audio/") == true:
            return "waveform"
        case "application/pdf":
            return "doc.text"
        case let mime where mime?.hasPrefix("text/") == true:
            return "doc.plaintext"
        default:
            return "doc"
        }
    }
}

/// Response from GET /api/library/tree
struct LibraryTreeResponse: Codable {
    let tree: [LibraryNode]
}

/// Response from GET /api/library/file-info
struct FileInfoResponse: Codable {
    let file: FileRecord
    let digests: [Digest]?
    let isPinned: Bool
}

/// Request body for POST /api/library/folder
struct CreateFolderRequest: Codable {
    let path: String
}

/// Request body for POST /api/library/rename
struct RenameRequest: Codable {
    let path: String
    let newName: String
}

/// Request body for POST /api/library/move
struct MoveRequest: Codable {
    let sourcePath: String
    let destinationPath: String
}

/// Request body for POST /api/library/pin and DELETE /api/library/pin
struct PinRequest: Codable {
    let path: String
}

/// Generic success response
struct SuccessResponse: Codable {
    let success: Bool
    let message: String?
}
