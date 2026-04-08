//
//  ExploreAPI.swift
//  MyLifeDB
//
//  Explore API endpoints.
//
//  Endpoints:
//  - GET    /api/explore/posts           - List posts (paginated)
//  - GET    /api/explore/posts/:id       - Get post with comments
//  - GET    /api/explore/posts/:id/comments - List comments
//  - DELETE /api/explore/posts/:id       - Delete post
//

import Foundation

/// API endpoints for Explore feed
struct ExploreAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - List

    /// List explore posts (newest first)
    func list(
        limit: Int = 30,
        before: String? = nil,
        after: String? = nil,
        ignoreCache: Bool = false
    ) async throws -> ExplorePostsResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let before {
            queryItems.append(URLQueryItem(name: "before", value: before))
        }
        if let after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }

        return try await client.request(
            path: "/api/explore/posts",
            queryItems: queryItems,
            ignoreCache: ignoreCache
        )
    }

    // MARK: - Detail

    /// Get a single post with its comments
    func get(id: String) async throws -> ExplorePostWithComments {
        try await client.request(path: "/api/explore/posts/\(id)")
    }

    // MARK: - Delete

    /// Delete a post
    func delete(id: String) async throws {
        try await client.requestVoid(
            path: "/api/explore/posts/\(id)",
            method: .delete
        )
    }
}

// MARK: - Convenience

extension ExploreAPI {

    /// Fetch next page (older posts)
    func fetchOlder(cursor: String, limit: Int = 30) async throws -> ExplorePostsResponse {
        try await list(limit: limit, before: cursor)
    }
}
