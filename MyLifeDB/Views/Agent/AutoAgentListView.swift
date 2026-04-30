//
//  AutoAgentListView.swift
//  MyLifeDB
//
//  Native auto-agent tree for the Agent tab's "Auto" section.
//  Mirrors the web's AutoAgentTree: each agent definition is a collapsible
//  header row whose nested rows are the auto-run sessions belonging to that
//  agent.  Sessions whose agent definition has been deleted appear in a
//  trailing "(unknown agent)" group.
//
//  - Tap a session row → push AgentSessionDetailView (same destination as
//    the Sessions tab).
//  - Tap the agent header / pencil → push AutoAgentEditorView for that name.
//  - Tap the "+ New auto agent" row → push the create-agent composer.
//

import SwiftUI

struct AutoAgentListView: View {

    /// Pushed by the parent NavigationStack when a row is selected.
    @Binding var path: NavigationPath

    /// Auto-run sessions, already filtered to `source == "auto"` by the
    /// parent.  Mirrors how the web passes its filtered `visibleSessions`
    /// down to AutoAgentTree.
    let sessions: [AgentSession]

    @State private var defs: [AgentDef] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var refreshTick: Int = 0
    @State private var collapsed: Set<String> = []

    var body: some View {
        Group {
            if isLoading && defs.isEmpty {
                loadingView
            } else if let error = error, defs.isEmpty {
                errorView(error)
            } else if defs.isEmpty && sessions.isEmpty {
                emptyView
            } else {
                tree
            }
        }
        .task(id: refreshTick) {
            await fetch()
        }
        .refreshable {
            await fetch()
        }
        .onAppear {
            // Refresh whenever the view re-appears (e.g. coming back from
            // the editor) so renames/deletes show up immediately.
            refreshTick &+= 1
        }
    }

    // MARK: - Grouping

    private struct AgentGroup: Identifiable {
        let key: String
        let def: AgentDef?
        let sessions: [AgentSession]
        let latestActivity: Int64
        var id: String { key }
        var displayName: String { def?.name ?? "(unknown agent)" }
        var isOrphan: Bool { def == nil }
    }

    private static let unknownAgentGroupKey = "__unknown__"

    /// Group sessions by `agentName`, mirroring the web's `groups` memo.
    private var groups: [AgentGroup] {
        var byAgent: [String: [AgentSession]] = [:]
        let knownNames = Set(defs.map(\.name))

        for s in sessions {
            let key: String
            if let name = s.agentName, knownNames.contains(name) {
                key = name
            } else {
                key = Self.unknownAgentGroupKey
            }
            byAgent[key, default: []].append(s)
        }

        // Sort sessions within each group, latest first.
        for k in byAgent.keys {
            byAgent[k]?.sort { a, b in
                (a.lastUserActivity ?? a.lastActivity) > (b.lastUserActivity ?? b.lastActivity)
            }
        }

        var result: [AgentGroup] = defs.map { def in
            let list = byAgent[def.name] ?? []
            return AgentGroup(
                key: def.name,
                def: def,
                sessions: list,
                latestActivity: list.first.map { $0.lastUserActivity ?? $0.lastActivity } ?? 0
            )
        }

        // Orphan group for sessions whose def has been deleted.
        if let orphans = byAgent[Self.unknownAgentGroupKey], !orphans.isEmpty {
            result.append(AgentGroup(
                key: Self.unknownAgentGroupKey,
                def: nil,
                sessions: orphans,
                latestActivity: orphans[0].lastUserActivity ?? orphans[0].lastActivity
            ))
        }

        // Sort: groups with sessions by latest activity desc; groups without
        // sessions to the bottom, alphabetically among themselves.
        result.sort { a, b in
            let aHas = !a.sessions.isEmpty
            let bHas = !b.sessions.isEmpty
            if aHas != bHas { return aHas }
            if aHas { return a.latestActivity > b.latestActivity }
            return a.displayName.localizedCompare(b.displayName) == .orderedAscending
        }

        return result
    }

    // MARK: - Tree

    private var tree: some View {
        List {
            // "+ New auto agent" row
            Button {
                path.append(AutoAgentDestination.create)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                    Text("New Auto Agent")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)

            ForEach(groups) { group in
                groupSection(group)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func groupSection(_ group: AgentGroup) -> some View {
        let isCollapsed = collapsed.contains(group.key)

        // Header row: chevron + name + (off) badge + pencil
        Button {
            toggle(group.key)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                if !group.isOrphan {
                    Circle()
                        .fill(personaColor(for: group.displayName))
                        .frame(width: 8, height: 8)
                }

                Text(group.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(group.isOrphan ? .secondary : .primary)
                    .italic(group.isOrphan)
                    .lineLimit(1)

                if let def = group.def, !def.enabled {
                    Text("OFF")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                        )
                }

                Spacer()

                if let def = group.def {
                    Button {
                        path.append(AutoAgentDestination.editor(name: def.name))
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)

        if !isCollapsed {
            if group.sessions.isEmpty && !group.isOrphan {
                Text("No sessions yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 30)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(group.sessions) { session in
                    autoSessionRow(session)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    private func autoSessionRow(_ session: AgentSession) -> some View {
        Button {
            path.append(AgentDestination.session(session))
        } label: {
            HStack(spacing: 8) {
                // Indent under the chevron
                Color.clear.frame(width: 22, height: 1)

                Text(session.title.replacing(/\s*\n\s*/, with: " "))
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(session.isArchived ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if session.sessionState == .working || session.sessionState == .unread {
                    Circle()
                        .fill(session.sessionState == .working ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                }

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(shortRelativeTime((session.lastUserActivity ?? session.lastActivity).asDate, now: context.date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ key: String) {
        if collapsed.contains(key) {
            collapsed.remove(key)
        } else {
            collapsed.insert(key)
        }
    }

    private func shortRelativeTime(_ date: Date, now: Date) -> String {
        // Compact numeric abbreviations (locale-independent for tight cells).
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading agents…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Failed to Load Agents")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await fetch() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No auto agents yet")
                .font(.headline)
            Text("Create an auto-run agent that responds to triggers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                path.append(AutoAgentDestination.create)
            } label: {
                Label("New Auto Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func fetch() async {
        isLoading = true
        error = nil
        do {
            let result = try await APIClient.shared.agent.listDefs()
            defs = result
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

// MARK: - Navigation

enum AutoAgentDestination: Hashable {
    case editor(name: String)
    case create
}

// MARK: - Persona Color

/// Palette mirroring the web's PERSONA_COLORS (rose/amber/emerald/sky/...
/// at /90 opacity). Order kept identical so the same agent gets the same
/// color across web and iOS.
private let personaPalette: [Color] = [
    Color(red: 0.96, green: 0.30, blue: 0.42),  // rose-500
    Color(red: 0.96, green: 0.62, blue: 0.04),  // amber-500
    Color(red: 0.13, green: 0.77, blue: 0.37),  // emerald-500
    Color(red: 0.05, green: 0.65, blue: 0.91),  // sky-500
    Color(red: 0.55, green: 0.36, blue: 0.96),  // violet-500
    Color(red: 0.93, green: 0.28, blue: 0.60),  // pink-500
    Color(red: 0.08, green: 0.72, blue: 0.65),  // teal-500
    Color(red: 0.39, green: 0.40, blue: 0.95),  // indigo-500
    Color(red: 0.98, green: 0.45, blue: 0.09),  // orange-500
    Color(red: 0.52, green: 0.80, blue: 0.09),  // lime-500
]

/// Match the web's hash: ((hash * 31 + charCode) >>> 0) over UTF-16 code
/// units. Produces identical persona colors across platforms.
private func personaColor(for name: String) -> Color {
    var hash: UInt32 = 0
    for unit in name.utf16 {
        hash = hash &* 31 &+ UInt32(unit)
    }
    return personaPalette[Int(hash % UInt32(personaPalette.count))]
}

// MARK: - Preview

#Preview {
    @Previewable @State var path = NavigationPath()
    return NavigationStack(path: $path) {
        AutoAgentListView(path: $path, sessions: [])
            .navigationTitle("Auto Agents")
    }
}
