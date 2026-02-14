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
    @State private var showNewSession = false
    @State private var selectedSession: ClaudeSession?

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
            .navigationTitle("Sessions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $selectedSession) { session in
                ClaudeSessionDetailView(session: session, claudeVM: claudeVM)
            }
            .navigationDestination(isPresented: $showNewSession) {
                NewClaudeSessionView(claudeVM: claudeVM)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedSession = nil
                        claudeVM.loadPath("/claude")
                        showNewSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            if sessions.isEmpty {
                await fetchSessions()
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                Button {
                    selectedSession = session
                } label: {
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if session.isArchived {
                        Button {
                            Task { await unarchiveSession(session) }
                        } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            Task { await archiveSession(session) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                }
                #endif
                .contextMenu {
                    if session.isArchived {
                        Button {
                            Task { await unarchiveSession(session) }
                        } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button {
                            Task { await archiveSession(session) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
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
        .listStyle(.plain)
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
                status: "active"
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
                status: "active"
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
                status: "active"
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

    // MARK: - Archive / Unarchive

    private func archiveSession(_ session: ClaudeSession) async {
        // Optimistic update — remove from list (always showing active)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: index)
        }

        do {
            try await APIClient.shared.claude.archive(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[ClaudeSessionListView] Archive failed: \(error)")
            await refresh()
        }
    }

    private func unarchiveSession(_ session: ClaudeSession) async {
        // Optimistic update
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session.withStatus("active")
        }

        do {
            try await APIClient.shared.claude.unarchive(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[ClaudeSessionListView] Unarchive failed: \(error)")
            await refresh()
        }
    }
}

// MARK: - New Session View

private struct NewClaudeSessionView: View {

    let claudeVM: TabWebViewModel

    var body: some View {
        ZStack {
            WebViewContainer(viewModel: claudeVM)

            if !claudeVM.isLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.platformBackground)
            }
        }
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #else
        .navigationTitle("New Session")
        #endif
        .onDisappear {
            claudeVM.navigateTo(path: "/claude")
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {

    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title
            HStack(spacing: 6) {
                Text(session.title)
                    .font(.body)
                    .lineLimit(1)

                if session.isArchived {
                    Image(systemName: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Meta: project · branch · msgs · time
            HStack(spacing: 4) {
                if let projectName = session.workingDir.split(separator: "/").last {
                    Text(String(projectName))
                }

                if let git = session.git, let branch = git.branch {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(branch)
                }

                if session.messageCount > 0 {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(session.messageCount) msgs")
                }

                Text("·")
                    .foregroundStyle(.quaternary)
                Text(session.lastActivity, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
        .opacity(session.isArchived ? 0.6 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    ClaudeSessionListView(claudeVM: TabWebViewModel(route: "/claude"))
}
