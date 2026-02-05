//
//  SearchAPI.swift
//  MyLifeDB
//
//  Search API endpoints.
//
//  Endpoints:
//  - GET /api/search - Full-text and semantic search
//

import Foundation

/// API endpoints for search
struct SearchAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Search

    /// Perform a search query
    /// - Parameters:
    ///   - query: Search query string (min 2 characters)
    ///   - limit: Number of results (default 20)
    ///   - offset: Pagination offset
    func search(
        query: String,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SearchResponse {
        guard query.count >= 2 else {
            throw APIError.badRequest("Query must be at least 2 characters")
        }

        return try await client.request(
            path: "/api/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        )
    }

    /// Search with pagination
    func searchNextPage(
        query: String,
        currentOffset: Int,
        limit: Int = 20
    ) async throws -> SearchResponse {
        try await search(query: query, limit: limit, offset: currentOffset + limit)
    }
}

// MARK: - Search Convenience

extension SearchAPI {

    /// Quick search with default settings
    func quickSearch(_ query: String) async throws -> [SearchResultItem] {
        let response = try await search(query: query)
        return response.results
    }
}
