//
//  ClaudeAPI.swift
//  MyLifeDB
//
//  Claude session API endpoints.
//
//  Endpoints:
//  - GET /api/claude/sessions/all  - List all sessions (paginated)
//

import Foundation

/// API endpoints for Claude session management
struct ClaudeAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - List Operations

    /// List all Claude sessions (newest first)
    /// - Parameters:
    ///   - limit: Number of sessions to fetch (default 20, max 100)
    ///   - cursor: Pagination cursor from previous response
    ///   - status: Filter by status ("all", "active", "archived"). "active" = not archived (default).
    func listAll(
        limit: Int = 20,
        cursor: String? = nil,
        status: String = "active"
    ) async throws -> ClaudeSessionsResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "status", value: status)
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try await client.request(
            path: "/api/claude/sessions/all",
            queryItems: queryItems
        )
    }

    // MARK: - Archive/Unarchive Operations

    /// Archive a Claude session from the default session list
    func archive(sessionId: String) async throws {
        try await client.requestVoid(
            path: "/api/claude/sessions/\(sessionId)/archive",
            method: .post
        )
    }

    /// Unarchive a Claude session (make it visible in the default session list)
    func unarchive(sessionId: String) async throws {
        try await client.requestVoid(
            path: "/api/claude/sessions/\(sessionId)/unarchive",
            method: .post
        )
    }
}
