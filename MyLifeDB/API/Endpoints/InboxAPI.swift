//
//  InboxAPI.swift
//  MyLifeDB
//
//  Inbox API endpoints.
//
//  Endpoints:
//  - GET    /api/inbox           - List inbox items (paginated)
//  - POST   /api/inbox           - Create inbox item
//  - GET    /api/inbox/pinned    - List pinned items
//  - GET    /api/inbox/:id       - Get single item
//  - PUT    /api/inbox/:id       - Update item content
//  - DELETE /api/inbox/:id       - Delete item
//  - POST   /api/inbox/:id/reenrich - Re-process item
//  - GET    /api/inbox/:id/status   - Get processing status
//

import Foundation

/// API endpoints for inbox management
struct InboxAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - List Operations

    /// List inbox items (newest first)
    /// - Parameters:
    ///   - limit: Number of items to fetch (default 30, max 100)
    ///   - before: Cursor for fetching older items
    ///   - after: Cursor for fetching newer items
    ///   - around: Cursor for fetching items around a specific item
    func list(
        limit: Int = 30,
        before: String? = nil,
        after: String? = nil,
        around: String? = nil
    ) async throws -> InboxResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let before = before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }
        if let around = around {
            queryItems.append(URLQueryItem(name: "around", value: around))
        }

        return try await client.request(
            path: "/api/inbox",
            queryItems: queryItems
        )
    }

    /// List pinned inbox items
    func listPinned() async throws -> PinnedInboxResponse {
        try await client.request(path: "/api/inbox/pinned")
    }

    // MARK: - CRUD Operations

    /// Get a single inbox item by ID (filename without "inbox/" prefix)
    func get(id: String) async throws -> InboxItem {
        try await client.request(path: "/api/inbox/\(id)")
    }

    /// Create a new inbox item with text content
    func createText(_ text: String) async throws -> CreateInboxResponse {
        try await client.uploadMultipart(
            path: "/api/inbox",
            formFields: ["text": text]
        )
    }

    /// Create a new inbox item by uploading files
    func uploadFiles(
        _ files: [(filename: String, data: Data, mimeType: String)],
        text: String? = nil
    ) async throws -> CreateInboxResponse {
        var formFields: [String: String] = [:]
        if let text = text {
            formFields["text"] = text
        }

        let fileUploads = files.map { file in
            (name: "files", filename: file.filename, data: file.data, mimeType: file.mimeType)
        }

        return try await client.uploadMultipart(
            path: "/api/inbox",
            formFields: formFields,
            files: fileUploads
        )
    }

    /// Update inbox item content
    func update(id: String, content: String) async throws {
        struct UpdateBody: Codable {
            let content: String
        }

        try await client.requestVoid(
            path: "/api/inbox/\(id)",
            method: .put,
            body: UpdateBody(content: content)
        )
    }

    /// Delete an inbox item
    func delete(id: String) async throws {
        try await client.requestVoid(
            path: "/api/inbox/\(id)",
            method: .delete
        )
    }

    // MARK: - Processing Operations

    /// Trigger re-enrichment (re-process digests) for an item
    func reenrich(id: String) async throws {
        try await client.requestVoid(
            path: "/api/inbox/\(id)/reenrich",
            method: .post
        )
    }

    /// Get processing status for an inbox item
    func getStatus(id: String) async throws -> InboxItemStatusResponse {
        try await client.request(path: "/api/inbox/\(id)/status")
    }
}

// MARK: - Convenience Extensions

extension InboxAPI {

    /// Fetch the next page of items (older)
    func fetchOlder(cursor: String, limit: Int = 30) async throws -> InboxResponse {
        try await list(limit: limit, before: cursor)
    }

    /// Fetch newer items
    func fetchNewer(cursor: String, limit: Int = 30) async throws -> InboxResponse {
        try await list(limit: limit, after: cursor)
    }

    /// Extract ID from inbox item path
    static func idFromPath(_ path: String) -> String {
        if path.hasPrefix("inbox/") {
            return String(path.dropFirst(6))
        }
        return path
    }
}
