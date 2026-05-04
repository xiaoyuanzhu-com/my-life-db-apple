//
//  LibraryAPI.swift
//  MyLifeDB
//
//  Library API endpoints for file management.
//
//  Endpoints (post Phase B refactor — see my-life-db-docs internal/api/api-structure.md):
//  - GET    /api/data/tree            - Get folder tree structure
//  - GET    /api/data/files/*path     - Get file details
//  - POST   /api/data/folders         - Create new folder ({parent, name})
//  - PATCH  /api/data/files/*path     - Rename ({name}) or move ({parent})
//  - DELETE /api/data/files/*path     - Delete file/folder
//  - PUT    /api/data/pins/*path      - Pin a file (idempotent)
//  - DELETE /api/data/pins/*path      - Unpin a file (idempotent)
//  - PUT    /api/data/uploads/simple/*path  - Simple file upload
//

import Foundation

/// API endpoints for library management
struct LibraryAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Path Encoding

    /// Encode a relative path for use as a URL path segment.
    /// Splits on "/" and percent-encodes each segment so that names containing
    /// "/", "?", "#", spaces, etc. are preserved.
    private static func encodePath(_ path: String) -> String {
        let trimmed = path.drop(while: { $0 == "/" })
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        return segments.map { segment in
            segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/")))
                ?? String(segment)
        }.joined(separator: "/")
    }

    /// Split a full path into (parent, name).
    /// e.g. "notes/2024/foo.md" -> ("notes/2024", "foo.md")
    /// e.g. "foo.md" -> ("", "foo.md")
    private static func splitParentAndName(_ path: String) -> (parent: String, name: String) {
        let trimmed = path.drop(while: { $0 == "/" })
        if let lastSlash = trimmed.lastIndex(of: "/") {
            let parent = String(trimmed[trimmed.startIndex..<lastSlash])
            let name = String(trimmed[trimmed.index(after: lastSlash)...])
            return (parent, name)
        }
        return ("", String(trimmed))
    }

    // MARK: - Tree Operations

    /// Get the folder tree structure (legacy — returns LibraryTreeResponse)
    func getTree() async throws -> LibraryTreeResponse {
        try await client.request(path: "/api/data/tree")
    }

    /// Get the folder tree structure for a specific path and depth.
    /// - Parameters:
    ///   - path: Directory path to list (empty string for root).
    ///   - depth: Recursion depth (1 = direct children only, 0 = unlimited).
    /// - Returns: FileTreeResponse with basePath, path, and children.
    func getTree(path: String = "", depth: Int = 1, ignoreCache: Bool = false) async throws -> FileTreeResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "depth", value: String(depth))
        ]
        if !path.isEmpty {
            queryItems.append(URLQueryItem(name: "path", value: path))
        }
        return try await client.request(
            path: "/api/data/tree",
            queryItems: queryItems,
            ignoreCache: ignoreCache
        )
    }

    /// Get file information
    func getFileInfo(path: String) async throws -> FileInfoResponse {
        try await client.request(
            path: "/api/data/files/\(Self.encodePath(path))"
        )
    }

    // MARK: - File Operations

    /// Create a new folder. The `path` is the full folder path; the API splits
    /// it into (parent, name) before sending to the backend.
    func createFolder(path: String) async throws -> SuccessResponse {
        let (parent, name) = Self.splitParentAndName(path)
        return try await client.request(
            path: "/api/data/folders",
            method: .post,
            body: CreateFolderRequest(parent: parent, name: name)
        )
    }

    /// Rename a file or folder
    func rename(path: String, newName: String) async throws -> SuccessResponse {
        try await client.request(
            path: "/api/data/files/\(Self.encodePath(path))",
            method: .patch,
            body: PatchFileRenameRequest(name: newName)
        )
    }

    /// Move a file or folder. `destinationPath` is the full new path; the
    /// parent directory is extracted and sent as the new parent.
    func move(from sourcePath: String, to destinationPath: String) async throws -> SuccessResponse {
        let (parent, _) = Self.splitParentAndName(destinationPath)
        return try await client.request(
            path: "/api/data/files/\(Self.encodePath(sourcePath))",
            method: .patch,
            body: PatchFileMoveRequest(parent: parent)
        )
    }

    /// Delete a file or folder
    func delete(path: String) async throws {
        try await client.requestVoid(
            path: "/api/data/files/\(Self.encodePath(path))",
            method: .delete
        )
    }

    // MARK: - Upload Operations

    /// Upload a file to the library using the simple upload endpoint.
    /// Sends raw file data as body with Content-Type header.
    /// - Parameters:
    ///   - data: The raw file data to upload.
    ///   - filename: The filename (will be sanitized server-side).
    ///   - destination: The destination folder path (empty string for root).
    ///   - mimeType: The MIME type of the file.
    /// - Returns: SuccessResponse with the final path.
    func simpleUpload(data: Data, filename: String, destination: String, mimeType: String) async throws -> SimpleUploadResponse {
        let uploadPath: String
        if destination.isEmpty {
            uploadPath = "/api/data/uploads/simple/\(filename)"
        } else {
            uploadPath = "/api/data/uploads/simple/\(destination)/\(filename)"
        }
        return try await client.uploadRaw(
            path: uploadPath,
            data: data,
            contentType: mimeType
        )
    }

    // MARK: - Pin Operations

    /// Pin a file (idempotent — PUT)
    func pin(path: String) async throws -> SuccessResponse {
        try await client.request(
            path: "/api/data/pins/\(Self.encodePath(path))",
            method: .put
        )
    }

    /// Unpin a file (idempotent — DELETE)
    func unpin(path: String) async throws {
        try await client.requestVoid(
            path: "/api/data/pins/\(Self.encodePath(path))",
            method: .delete
        )
    }
}

// MARK: - Raw File Operations

extension LibraryAPI {

    /// Get raw file content
    func getRawContent(path: String) async throws -> Data {
        try await client.getRawFile(path: path)
    }

    /// Save raw file content
    func saveRawContent(path: String, data: Data) async throws {
        try await client.saveRawFile(path: path, data: data)
    }

    /// Get screenshot from sqlar archive
    func getScreenshot(sqlarPath: String) async throws -> Data {
        try await client.getSqlarFile(path: sqlarPath)
    }

    /// Build URL for raw file (for use with AsyncImage, etc.)
    func rawFileURL(path: String) -> URL {
        client.rawFileURL(path: path)
    }

    /// Build URL for sqlar file (for use with AsyncImage, etc.)
    func sqlarFileURL(path: String) -> URL {
        client.sqlarFileURL(path: path)
    }
}
