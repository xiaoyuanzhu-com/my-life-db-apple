//
//  SettingsAPI.swift
//  MyLifeDB
//
//  Settings API endpoints.
//
//  Endpoints:
//  - GET  /api/system/settings    - Get current settings
//  - PUT  /api/system/settings    - Update settings
//  - POST /api/system/settings    - Reset settings
//  - GET  /api/system/stats       - Application statistics
//  - GET  /api/data/directories   - Available directories
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
        try await client.request(path: "/api/system/settings")
    }

    /// Update settings
    func update(_ settings: UpdateSettingsRequest) async throws {
        try await client.requestVoid(
            path: "/api/system/settings",
            method: .put,
            body: settings
        )
    }

    /// Reset settings to defaults
    func reset() async throws {
        try await client.requestVoid(
            path: "/api/system/settings",
            method: .post
        )
    }
}

// MARK: - Stats API

extension APIClient {

    /// Get application statistics
    func getStats() async throws -> StatsResponse {
        try await request(path: "/api/system/stats")
    }

    /// Get available directories
    func getDirectories() async throws -> DirectoriesResponse {
        try await request(path: "/api/data/directories")
    }
}

/// Response from GET /api/system/stats
struct StatsResponse: Codable {
    // Add stats properties based on your backend
    let totalFiles: Int?
    let totalFolders: Int?
}

/// Response from GET /api/data/directories
struct DirectoriesResponse: Codable {
    let directories: [String]
}
