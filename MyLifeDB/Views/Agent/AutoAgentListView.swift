//
//  AutoAgentListView.swift
//  MyLifeDB
//
//  Native grid of auto-run agent definitions. Mirrors the web's
//  AutoAgentList: avatar tile per agent (persona color from name hash),
//  initials, "off" badge for disabled defs, and a trailing "+" tile to
//  create a new agent (which seeds the new-session composer with the
//  /create-agent skill, exactly like the web).
//
//  Tapping a tile opens AutoAgentEditorView (a WebView pinned to the
//  /agent/auto?edit=<name> route).
//

import SwiftUI

struct AutoAgentListView: View {

    /// Pushed by the parent NavigationStack when a tile is selected.
    @Binding var path: NavigationPath

    @State private var defs: [AgentDef] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var refreshTick: Int = 0

    var body: some View {
        Group {
            if isLoading && defs.isEmpty {
                loadingView
            } else if let error = error, defs.isEmpty {
                errorView(error)
            } else {
                grid
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

    // MARK: - Subviews

    private var grid: some View {
        // Avatar tiles ~ 96pt wide, mirroring the web's auto-fill 8rem grid.
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 16)],
                alignment: .center,
                spacing: 20
            ) {
                ForEach(defs) { def in
                    Button {
                        path.append(AutoAgentDestination.editor(name: def.name))
                    } label: {
                        AgentTile(name: def.name, enabled: def.enabled)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    path.append(AutoAgentDestination.create)
                } label: {
                    NewAgentTile()
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

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

// MARK: - Tiles

private struct AgentTile: View {

    let name: String
    let enabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(personaColor(for: name))
                .frame(width: 56, height: 56)
                .overlay(
                    Text(personaInitials(for: name))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )

            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if !enabled {
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
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct NewAgentTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color.secondary.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                )

            Text("New")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Persona Color / Initials

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

private func personaInitials(for name: String) -> String {
    let cleaned = name
        .replacingOccurrences(of: "[^a-zA-Z0-9]", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    if cleaned.isEmpty { return "?" }
    let parts = cleaned.split(separator: " ", omittingEmptySubsequences: true)
    if parts.count >= 2 {
        let a = parts[0].first.map(String.init) ?? ""
        let b = parts[1].first.map(String.init) ?? ""
        return (a + b).uppercased()
    }
    return String(cleaned.prefix(2)).uppercased()
}

// MARK: - Preview

#Preview {
    @Previewable @State var path = NavigationPath()
    return NavigationStack(path: $path) {
        AutoAgentListView(path: $path)
            .navigationTitle("Auto Agents")
    }
}
