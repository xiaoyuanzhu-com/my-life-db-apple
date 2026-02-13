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
    var status: String        // "active" or "archived"
    let git: ClaudeSessionGitInfo?

    var isArchived: Bool { status == "archived" }

    /// Returns a copy with the given status
    func withStatus(_ newStatus: String) -> ClaudeSession {
        var copy = self
        copy.status = newStatus
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
