//
//  AgentAPI.swift
//  MyLifeDB
//
//  Agent session API endpoints.
//
//  Endpoints:
//  - GET /api/agent/sessions/all  - List all sessions (paginated)
//

import Foundation

/// API endpoints for agent session management
struct AgentAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - List Operations

    /// List all agent sessions (newest first)
    /// - Parameters:
    ///   - limit: Number of sessions to fetch (default 20, max 100)
    ///   - cursor: Pagination cursor from previous response
    ///   - status: Filter by status ("all", "active", "archived"). "active" = not archived (default).
    func listAll(
        limit: Int = 20,
        cursor: String? = nil,
        status: String = "active"
    ) async throws -> AgentSessionsResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "status", value: status)
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try await client.request(
            path: "/api/agent/sessions/all",
            queryItems: queryItems
        )
    }

    // MARK: - Archive/Unarchive Operations

    /// Archive an agent session from the default session list
    func archive(sessionId: String) async throws {
        try await client.requestVoid(
            path: "/api/agent/sessions/\(sessionId)/archive",
            method: .post
        )
    }

    /// Unarchive an agent session (make it visible in the default session list)
    func unarchive(sessionId: String) async throws {
        try await client.requestVoid(
            path: "/api/agent/sessions/\(sessionId)/unarchive",
            method: .post
        )
    }
}
