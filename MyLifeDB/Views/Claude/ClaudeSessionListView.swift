//
//  ClaudeSessionListView.swift
//  MyLifeDB
//
//  Native session list for the Claude tab.
//  Fetches sessions from the API and displays them in a SwiftUI List.
//  Tapping a session navigates to a WebView showing that session.
//

import SwiftUI

// MARK: - Navigation Destination

enum ClaudeDestination: Hashable {
    case session(ClaudeSession)
    case newSession
}

struct ClaudeSessionListView: View {

    let claudeVM: TabWebViewModel

    @State private var sessions: [ClaudeSession] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var destination: ClaudeDestination?
    @State private var sseManager = ClaudeSessionSSEManager()

    /// ID of the session that was just viewed — drives the return highlight animation
    @State private var highlightedSessionId: String?

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
            .navigationDestination(item: $destination) { dest in
                switch dest {
                case .session(let session):
                    ClaudeSessionDetailView(session: session, claudeVM: claudeVM)
                case .newSession:
                    NewClaudeSessionView(claudeVM: claudeVM)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        claudeVM.loadPath("/claude")
                        destination = .newSession
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
            setupSSE()
        }
        .onDisappear {
            sseManager.stop()
        }
        .onChange(of: destination) { oldValue, newValue in
            if newValue == nil, let old = oldValue {
                // Returned from a destination — refresh the list
                Task { await refresh() }
                // If returning from a session detail, trigger the breath highlight
                if case .session(let session) = old {
                    highlightedSessionId = session.id
                }
            }
        }
    }

    // MARK: - Session List

    private var groupedSessions: [(title: String, sessions: [ClaudeSession])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday),
              let startOfMonth = calendar.date(byAdding: .month, value: -1, to: startOfToday)
        else { return [("All", sessions)] }

        var today: [ClaudeSession] = []
        var yesterday: [ClaudeSession] = []
        var pastWeek: [ClaudeSession] = []
        var pastMonth: [ClaudeSession] = []
        var earlier: [ClaudeSession] = []

        for session in sessions {
            let date = session.lastUserActivity ?? session.lastActivity
            if date >= startOfToday {
                today.append(session)
            } else if date >= startOfYesterday {
                yesterday.append(session)
            } else if date >= startOfWeek {
                pastWeek.append(session)
            } else if date >= startOfMonth {
                pastMonth.append(session)
            } else {
                earlier.append(session)
            }
        }

        var result: [(String, [ClaudeSession])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !pastWeek.isEmpty { result.append(("Past Week", pastWeek)) }
        if !pastMonth.isEmpty { result.append(("Past Month", pastMonth)) }
        if !earlier.isEmpty { result.append(("Earlier", earlier)) }
        return result
    }

    private var sessionList: some View {
        List {
            ForEach(groupedSessions, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sessions) { session in
                        sessionButton(session)
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

    private func sessionButton(_ session: ClaudeSession) -> some View {
        Button {
            destination = .session(session)
        } label: {
            SessionRow(session: session)
                .contentShape(Rectangle())
                .overlay(returnHighlight(for: session.id))
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

    // MARK: - Return Highlight ("breath" effect)

    /// Phases: idle → breathe in → hold → breathe out → clear highlight ID
    private enum HighlightPhase: CaseIterable {
        case idle, breatheIn, hold, breatheOut

        var opacity: Double {
            switch self {
            case .idle:       0
            case .breatheIn:  0.18
            case .hold:       0.12
            case .breatheOut: 0
            }
        }
    }

    @ViewBuilder
    private func returnHighlight(for id: String) -> some View {
        if highlightedSessionId == id {
            // PhaseAnimator cycles through all phases once per trigger change
            PhaseAnimator(HighlightPhase.allCases, trigger: highlightedSessionId) { phase in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(phase.opacity))
                    .allowsHitTesting(false)
            } animation: { phase in
                switch phase {
                case .idle:       .smooth(duration: 0.01)   // instant reset
                case .breatheIn:  .smooth(duration: 0.4)    // gentle fade in
                case .hold:       .smooth(duration: 0.6)    // subtle dim while holding
                case .breatheOut: .smooth(duration: 0.8)    // long, gentle fade out
                }
            }
            .onDisappear {
                highlightedSessionId = nil
            }
            // Auto-clear after the full cycle so PhaseAnimator doesn't loop
            .task {
                try? await Task.sleep(for: .seconds(2.0))
                highlightedSessionId = nil
            }
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

    // MARK: - SSE

    private func setupSSE() {
        sseManager.onSessionUpdated = {
            Task { await refresh() }
        }
        sseManager.start()
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
        // Optimistic update — remove from list with spring animation
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            let _ = withAnimation(.snappy(duration: 0.35)) {
                sessions.remove(at: index)
            }
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
        HStack {
            Text(session.title)
                .lineLimit(1)

            Spacer()

            // Show activity indicator if Claude is actively working
            // (lastActivity is more recent than lastUserActivity by > 10s)
            if let userTime = session.lastUserActivity,
               session.lastActivity.timeIntervalSince(userTime) > 10 {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text(shortRelativeTime(session.lastUserActivity ?? session.lastActivity))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .opacity(session.isArchived ? 0.6 : 1.0)
    }

    private func shortRelativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}

// MARK: - Preview

#Preview {
    ClaudeSessionListView(claudeVM: TabWebViewModel(route: "/claude"))
}
