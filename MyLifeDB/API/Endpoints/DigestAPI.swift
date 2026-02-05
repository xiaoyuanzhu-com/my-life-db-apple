//
//  DigestAPI.swift
//  MyLifeDB
//
//  Digest API endpoints.
//
//  Endpoints:
//  - GET    /api/digest/digesters        - List registered digesters
//  - GET    /api/digest/stats            - Get digest statistics
//  - GET    /api/digest/file/*path       - Get digests for a file
//  - POST   /api/digest/file/*path       - Trigger digest processing
//  - DELETE /api/digest/reset/:digester  - Reset a digester
//

import Foundation

/// API endpoints for digest management
struct DigestAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Digester Info

    /// List all registered digesters
    func listDigesters() async throws -> DigestersResponse {
        try await client.request(path: "/api/digest/digesters")
    }

    /// Get digest processing statistics
    func getStats() async throws -> DigestStatsResponse {
        try await client.request(path: "/api/digest/stats")
    }

    // MARK: - File Digests

    /// Get digests for a specific file
    func getForFile(path: String) async throws -> [Digest] {
        try await client.request(path: "/api/digest/file/\(path)")
    }

    /// Trigger digest processing for a file
    func triggerForFile(path: String) async throws {
        try await client.requestVoid(
            path: "/api/digest/file/\(path)",
            method: .post
        )
    }

    // MARK: - Reset Operations

    /// Reset a specific digester (reprocess all files)
    func reset(digester: String) async throws {
        try await client.requestVoid(
            path: "/api/digest/reset/\(digester)",
            method: .delete
        )
    }
}
