//
//  AgentSession.swift
//  MyLifeDB
//
//  Agent session model matching backend ListAllAgentSessions response.
//

import Foundation

/// Unified session state computed by the backend from archive state,
/// read state, and processing state.
///
/// "unread" refers specifically to unread *result* messages (completed turns),
/// NOT intermediate messages like assistant text, tool calls, or progress
/// updates that stream while the agent is working.
enum SessionState: String, Codable, Hashable {
    case idle       // User is up to date, nothing needs attention
    case working    // Agent is mid-turn (processing)
    case unread     // Unread result messages or pending permission
    case archived   // User explicitly archived
}

/// Represents an agent session
struct AgentSession: Codable, Identifiable, Hashable {

    let id: String
    let title: String
    let workingDir: String
    let createdAt: Int64           // epoch milliseconds
    let lastActivity: Int64        // epoch milliseconds
    let lastUserActivity: Int64?   // epoch milliseconds — last user (not agent) interaction, used for stable list ordering
    let messageCount: Int
    let isSidechain: Bool
    var sessionState: SessionState
    let git: AgentSessionGitInfo?
    /// "user" (user-initiated chat) or "auto" (auto-run agent session).
    /// Used by the Agent tab to split sessions between the Sessions and Auto tabs.
    let source: String?
    /// Auto-agent definition name this session belongs to (only set when source == "auto").
    let agentName: String?

    var isArchived: Bool { sessionState == .archived }
    var isAuto: Bool { source == "auto" }

    /// Returns a copy with the given session state
    func withSessionState(_ state: SessionState) -> AgentSession {
        var copy = self
        copy.sessionState = state
        return copy
    }

    // Custom decoder to handle fields the backend may not include
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        workingDir = try container.decode(String.self, forKey: .workingDir)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        lastActivity = try container.decode(Int64.self, forKey: .lastActivity)
        lastUserActivity = try container.decodeIfPresent(Int64.self, forKey: .lastUserActivity)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        isSidechain = try container.decodeIfPresent(Bool.self, forKey: .isSidechain) ?? false
        sessionState = try container.decode(SessionState.self, forKey: .sessionState)
        git = try container.decodeIfPresent(AgentSessionGitInfo.self, forKey: .git)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
    }
}

/// Git repository info for an agent session
struct AgentSessionGitInfo: Codable, Hashable {
    let isRepo: Bool
    let branch: String?
    let remoteUrl: String?
}

// MARK: - API Response Types

/// Response from GET /api/agent/sessions/all
struct AgentSessionsResponse: Codable {
    let sessions: [AgentSession]
    let pagination: AgentSessionsPagination
}

/// Pagination info for session list
struct AgentSessionsPagination: Codable {
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
