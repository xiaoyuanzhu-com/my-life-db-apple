//
//  ClaudeSession.swift
//  MyLifeDB
//
//  Claude session model matching backend ListAllClaudeSessions response.
//

import Foundation

/// Unified session state computed by the backend from archive state,
/// read state, and processing state.
enum SessionState: String, Codable, Hashable {
    case idle       // No unread messages
    case working    // Has unread messages, Claude is still working
    case ready      // Has unread messages, Claude finished (needs user input)
    case archived   // User explicitly archived
}

/// Represents a Claude Code session
struct ClaudeSession: Codable, Identifiable, Hashable {

    let id: String
    let title: String
    let workingDir: String
    let createdAt: Date
    let lastActivity: Date
    let lastUserActivity: Date?  // Last user (not Claude) interaction — used for stable list ordering
    let messageCount: Int
    let isSidechain: Bool
    var sessionState: SessionState
    let git: ClaudeSessionGitInfo?

    var isArchived: Bool { sessionState == .archived }

    /// Returns a copy with the given session state
    func withSessionState(_ state: SessionState) -> ClaudeSession {
        var copy = self
        copy.sessionState = state
        return copy
    }
}

/// Git repository info for a Claude session
struct ClaudeSessionGitInfo: Codable, Hashable {
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
