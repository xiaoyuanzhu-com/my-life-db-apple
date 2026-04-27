//
//  AgentDef.swift
//  MyLifeDB
//
//  Auto-run agent definition model. Mirrors the AutoAgentSummary
//  shape returned by GET /api/agent/defs on the backend.
//

import Foundation

/// Summary of an auto-run agent definition (one row per markdown file in
/// the agents/ folder). Used by the auto-agents grid.
struct AgentDef: Codable, Identifiable, Hashable {

    /// Folder name of the agent (kebab-case). Doubles as the unique id.
    let name: String

    /// Underlying agent runner (e.g. "claude_code").
    let agent: String

    /// Trigger kind (e.g. "cron", "file.created", "manual").
    let trigger: String

    /// Cron schedule string when trigger is "cron".
    let schedule: String?

    /// Path glob when trigger is a file event.
    let path: String?

    /// Whether the definition is currently enabled.
    let enabled: Bool

    var id: String { name }
}

/// Response wrapper for GET /api/agent/defs
struct AgentDefsResponse: Codable {
    let defs: [AgentDef]
}
