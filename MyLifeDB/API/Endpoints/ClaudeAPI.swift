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

    /// List all Claude sessions (active + historical, newest first)
    /// - Parameters:
    ///   - limit: Number of sessions to fetch (default 20, max 100)
    ///   - cursor: Pagination cursor from previous response
    ///   - status: Filter by status ("all", "active", "archived")
    func listAll(
        limit: Int = 20,
        cursor: String? = nil,
        status: String = "all"
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
}
