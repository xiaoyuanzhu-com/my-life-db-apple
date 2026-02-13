//
//  ClaudeSession.swift
//  MyLifeDB
//
//  Claude session model matching backend ListAllClaudeSessions response.
//

import Foundation

/// Represents a Claude Code session
struct ClaudeSession: Codable, Identifiable {

    let id: String
    let title: String
    let workingDir: String
    let createdAt: Date
    let lastActivity: Date
    let messageCount: Int
    let isSidechain: Bool
    let isActive: Bool
    let status: String        // "active", "archived", "dead"
    var isArchived: Bool
    let processId: Int?
    let clients: Int?
    let git: ClaudeSessionGitInfo?

    /// Returns a copy with the archived state changed
    func withArchived(_ archived: Bool) -> ClaudeSession {
        var copy = self
        copy.isArchived = archived
        return copy
    }
}

/// Git repository info for a Claude session
struct ClaudeSessionGitInfo: Codable {
    let isRepo: Bool
    let branch: String?
    let remoteUrl: String?
}

// MARK: - API Response Types

/// Response from GET /api/claude/sessions/all
struct ClaudeSessionsResponse: Codable {
    let sessions: [ClaudeSession]
    let pagination: ClaudeSessionsPagination
}

/// Pagination info for session list
struct ClaudeSessionsPagination: Codable {
    let hasMore: Bool
    let nextCursor: String?
    let totalCount: Int
}
