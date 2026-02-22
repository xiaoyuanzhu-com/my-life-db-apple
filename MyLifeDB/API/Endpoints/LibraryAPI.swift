//
//  LibraryAPI.swift
//  MyLifeDB
//
//  Library API endpoints for file management.
//
//  Endpoints:
//  - GET    /api/library/tree       - Get folder tree structure
//  - GET    /api/library/file-info  - Get file details
//  - POST   /api/library/folder     - Create new folder
//  - POST   /api/library/rename     - Rename file/folder
//  - POST   /api/library/move       - Move file/folder
//  - DELETE /api/library/file       - Delete file/folder
//  - POST   /api/library/pin        - Pin a file
//  - DELETE /api/library/pin        - Unpin a file
//  - PUT    /api/upload/simple/*path - Simple file upload
//

import Foundation

/// API endpoints for library management
struct LibraryAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Tree Operations

    /// Get the folder tree structure (legacy — returns LibraryTreeResponse)
    func getTree() async throws -> LibraryTreeResponse {
        try await client.request(path: "/api/library/tree")
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
            path: "/api/library/tree",
            queryItems: queryItems,
            ignoreCache: ignoreCache
        )
    }

    /// Get file information with digests
    func getFileInfo(path: String) async throws -> FileInfoResponse {
        try await client.request(
            path: "/api/library/file-info",
            queryItems: [URLQueryItem(name: "path", value: path)]
        )
    }

    // MARK: - File Operations

    /// Create a new folder
    func createFolder(path: String) async throws -> SuccessResponse {
        try await client.request(
            path: "/api/library/folder",
            method: .post,
            body: CreateFolderRequest(path: path)
        )
    }

    /// Rename a file or folder
    func rename(path: String, newName: String) async throws -> SuccessResponse {
        try await client.request(
            path: "/api/library/rename",
            method: .post,
            body: RenameRequest(path: path, newName: newName)
        )
    }

    /// Move a file or folder
    func move(from sourcePath: String, to destinationPath: String) async throws -> SuccessResponse {
        try await client.request(
            path: "/api/library/move",
            method: .post,
            body: MoveRequest(sourcePath: sourcePath, destinationPath: destinationPath)
        )
    }

    /// Delete a file or folder
    func delete(path: String) async throws {
        try await client.requestVoid(
            path: "/api/library/file",
            method: .delete,
            queryItems: [URLQueryItem(name: "path", value: path)]
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
            uploadPath = "/api/upload/simple/\(filename)"
        } else {
            uploadPath = "/api/upload/simple/\(destination)/\(filename)"
        }
        return try await client.uploadRaw(
            path: uploadPath,
            data: data,
            contentType: mimeType
        )
    }

    // MARK: - Pin Operations

    /// Pin a file
    func pin(path: String) async throws -> SuccessResponse {
        try await client.request(
            path: "/api/library/pin",
            method: .post,
            body: PinRequest(path: path)
        )
    }

    /// Unpin a file
    func unpin(path: String) async throws {
        try await client.requestVoid(
            path: "/api/library/pin",
            method: .delete,
            queryItems: [URLQueryItem(name: "path", value: path)]
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
