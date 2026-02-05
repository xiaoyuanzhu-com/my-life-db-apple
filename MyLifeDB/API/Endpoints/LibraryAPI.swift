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
//

import Foundation

/// API endpoints for library management
struct LibraryAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Tree Operations

    /// Get the folder tree structure
    func getTree() async throws -> LibraryTreeResponse {
        try await client.request(path: "/api/library/tree")
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
