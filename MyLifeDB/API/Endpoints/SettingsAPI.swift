//
//  SettingsAPI.swift
//  MyLifeDB
//
//  Settings API endpoints.
//
//  Endpoints:
//  - GET  /api/settings - Get current settings
//  - PUT  /api/settings - Update settings
//  - POST /api/settings - Reset settings
//

import Foundation

/// API endpoints for settings management
struct SettingsAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Settings Operations

    /// Get current settings
    func get() async throws -> SettingsResponse {
        try await client.request(path: "/api/settings")
    }

    /// Update settings
    func update(_ settings: UpdateSettingsRequest) async throws {
        try await client.requestVoid(
            path: "/api/settings",
            method: .put,
            body: settings
        )
    }

    /// Reset settings to defaults
    func reset() async throws {
        try await client.requestVoid(
            path: "/api/settings",
            method: .post
        )
    }
}

// MARK: - Stats API

extension APIClient {

    /// Get application statistics
    func getStats() async throws -> StatsResponse {
        try await request(path: "/api/stats")
    }

    /// Get available directories
    func getDirectories() async throws -> DirectoriesResponse {
        try await request(path: "/api/directories")
    }
}

/// Response from GET /api/stats
struct StatsResponse: Codable {
    // Add stats properties based on your backend
    let totalFiles: Int?
    let totalFolders: Int?
    let inboxCount: Int?
}

/// Response from GET /api/directories
struct DirectoriesResponse: Codable {
    let directories: [String]
}
