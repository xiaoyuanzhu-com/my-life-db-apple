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

// MARK: - Tree API Response Models

/// A node in the tree response from GET /api/library/tree.
/// Note: `path` is just the filename/folder name, NOT the full path.
/// The parent directory is implicit from the API request context.
struct FileTreeNode: Codable, Identifiable, Hashable {

    // MARK: - Identifiable

    var id: String { path }

    // MARK: - Properties

    /// Filename or folder name (NOT full path)
    let path: String
    /// "file" or "folder"
    let type: String
    /// File size in bytes (nil for folders)
    let size: Int64?
    /// ISO 8601 modification timestamp
    let modifiedAt: String?
    /// Children (populated for folders when depth allows)
    let children: [FileTreeNode]?

    // MARK: - Computed Properties

    /// Whether this node is a folder
    var isFolder: Bool { type == "folder" }

    /// Display name (same as path since path = name in tree response)
    var name: String { path }

    /// File extension (lowercased)
    var fileExtension: String? {
        guard !isFolder else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// SF Symbol name based on file extension (tree response has no mimeType)
    var systemImage: String {
        if isFolder { return "folder.fill" }
        guard let ext = fileExtension else { return "doc" }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "svg", "tiff", "bmp", "ico":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return "video"
        case "mp3", "wav", "m4a", "aac", "ogg", "flac", "wma":
            return "waveform"
        case "pdf":
            return "doc.text"
        case "md", "txt", "json", "xml", "yaml", "yml", "csv", "log", "ini", "conf", "toml",
             "swift", "go", "py", "js", "ts", "tsx", "jsx", "html", "css", "scss",
             "sh", "bash", "zsh", "fish", "rs", "c", "cpp", "h", "hpp", "java", "kt", "rb",
             "r", "sql", "graphql", "proto", "lua", "vim", "el", "ex", "exs", "erl":
            return "doc.plaintext"
        case "zip", "tar", "gz", "bz2", "xz", "rar", "7z":
            return "doc.zipper"
        default:
            return "doc"
        }
    }

    /// Formatted file size string
    var formattedSize: String? {
        guard let size = size else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Parsed modification date
    var modifiedDate: Date? {
        guard let modifiedAt = modifiedAt else { return nil }
        return ISO8601DateFormatter().date(from: modifiedAt)
    }
}

/// Response from GET /api/library/tree?path=&depth=
struct FileTreeResponse: Codable {
    let basePath: String?
    let path: String?
    let children: [FileTreeNode]
}
