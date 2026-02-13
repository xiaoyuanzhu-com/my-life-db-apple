//
//  ClaudeSessionListView.swift
//  MyLifeDB
//
//  Native session list for the Claude tab.
//  Fetches sessions from the API and displays them in a SwiftUI List.
//  Tapping a session navigates to a WebView showing that session.
//

import SwiftUI

struct ClaudeSessionListView: View {

    let claudeVM: TabWebViewModel

    @State private var sessions: [ClaudeSession] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var statusFilter: StatusFilter = .active

    enum StatusFilter: String, CaseIterable {
        case active
        case all
        case hidden

        var label: String {
            switch self {
            case .active: "Active"
            case .all: "All"
            case .hidden: "Hidden"
            }
        }

        /// API query parameter value
        var apiValue: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sessions.isEmpty {
                    loadingView
                } else if let error = error, sessions.isEmpty {
                    errorView(error)
                } else {
                    sessionList
                }
            }
            .navigationTitle("Claude")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .automatic) {
                    Picker("Filter", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases, id: \.self) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .task {
            if sessions.isEmpty {
                await fetchSessions()
            }
        }
        .onChange(of: statusFilter) {
            Task { await refresh() }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink {
                    ClaudeSessionDetailView(session: session, claudeVM: claudeVM)
                } label: {
                    SessionRow(session: session)
                }
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if session.isHidden {
                        Button {
                            Task { await unhideSession(session) }
                        } label: {
                            Label("Unhide", systemImage: "eye")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            Task { await hideSession(session) }
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                        .tint(.orange)
                    }
                }
                #endif
                .contextMenu {
                    if session.isHidden {
                        Button {
                            Task { await unhideSession(session) }
                        } label: {
                            Label("Unhide", systemImage: "eye")
                        }
                    } else {
                        Button {
                            Task { await hideSession(session) }
                        } label: {
                            Label("Hide", systemImage: "eye.slash")
                        }
                    }
                }
            }

            if hasMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .task {
                            await loadMore()
                        }
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Loading & Error Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading sessions...")
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

            Text("Failed to Load Sessions")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task { await fetchSessions() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Fetching

    private func fetchSessions() async {
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.claude.listAll(
                status: statusFilter.apiValue
            )
            sessions = response.sessions
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func refresh() async {
        nextCursor = nil
        hasMore = false

        do {
            let response = try await APIClient.shared.claude.listAll(
                status: statusFilter.apiValue
            )
            sessions = response.sessions
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
            error = nil
        } catch {
            self.error = error
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true

        do {
            let response = try await APIClient.shared.claude.listAll(
                cursor: cursor,
                status: statusFilter.apiValue
            )
            sessions.append(contentsOf: response.sessions)
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
        } catch {
            // Silently fail on load-more; user can scroll up and try again
            print("[ClaudeSessionListView] Load more failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Hide / Unhide

    private func hideSession(_ session: ClaudeSession) async {
        // Optimistic update
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            withAnimation {
                if statusFilter == .active {
                    // Remove from list when viewing active sessions
                    sessions.remove(at: index)
                } else {
                    // Update in-place when viewing all/hidden
                    sessions[index] = session.withHidden(true)
                }
            }
        }

        do {
            try await APIClient.shared.claude.hide(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[ClaudeSessionListView] Hide failed: \(error)")
            await refresh()
        }
    }

    private func unhideSession(_ session: ClaudeSession) async {
        // Optimistic update
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            withAnimation {
                if statusFilter == .hidden {
                    // Remove from list when viewing hidden sessions
                    sessions.remove(at: index)
                } else {
                    // Update in-place when viewing all/active
                    sessions[index] = session.withHidden(false)
                }
            }
        }

        do {
            try await APIClient.shared.claude.unhide(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[ClaudeSessionListView] Unhide failed: \(error)")
            await refresh()
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {

    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                // Title
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.body)
                        .lineLimit(2)

                    if session.isHidden {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Subtitle: working dir + metadata
                HStack(spacing: 6) {
                    // Project path (last component)
                    if let projectName = session.workingDir.split(separator: "/").last {
                        Text(String(projectName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Git branch
                    if let git = session.git, let branch = git.branch {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(branch)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Message count
                    if session.messageCount > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                        Text("\(session.messageCount) msgs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Relative time
                Text(session.lastActivity, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(session.isHidden ? 0.6 : 1.0)
    }

    private var statusColor: Color {
        switch session.status {
        case "active":
            return .green
        case "archived":
            return .gray
        case "dead":
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    ClaudeSessionListView(claudeVM: TabWebViewModel(route: "/claude"))
}
