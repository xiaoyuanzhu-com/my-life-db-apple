//
//  ClaudeSession.swift
//  MyLifeDB
//
//  Claude session model matching backend ListAllClaudeSessions response.
//

import Foundation

/// Unified session state computed by the backend from archive state,
/// read state, and processing state.
///
/// "unread" refers specifically to unread *result* messages (completed turns),
/// NOT intermediate messages like assistant text, tool calls, or progress
/// updates that stream while Claude is working.
enum SessionState: String, Codable, Hashable {
    case idle       // User is up to date, nothing needs attention
    case working    // Claude is mid-turn (processing)
    case unread     // Unread result messages or pending permission
    case archived   // User explicitly archived
}

/// Represents a Claude Code session
struct ClaudeSession: Codable, Identifiable, Hashable {

    let id: String
    let title: String
    let workingDir: String
    let createdAt: Int64           // epoch milliseconds
    let lastActivity: Int64        // epoch milliseconds
    let lastUserActivity: Int64?   // epoch milliseconds — last user (not Claude) interaction, used for stable list ordering
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

// MARK: - Epoch Millisecond Helpers

extension Int64 {
    /// Converts Unix epoch milliseconds to a Swift Date
    var asDate: Date {
        Date(timeIntervalSince1970: Double(self) / 1000.0)
    }
}
