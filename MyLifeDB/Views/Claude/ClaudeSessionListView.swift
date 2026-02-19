//
//  ClaudeSessionListView.swift
//  MyLifeDB
//
//  Native session list for the Claude tab.
//  Fetches sessions from the API and displays them in a SwiftUI List.
//  Tapping a session pushes a detail view with its own dedicated WebView.
//

import SwiftUI

// MARK: - Navigation Destination

enum ClaudeDestination: Hashable {
    case session(ClaudeSession)
    case sessionById(String)
    case newSession
}

struct ClaudeSessionListView: View {

    @Binding var deepLink: String?

    @Environment(\.scenePhase) private var scenePhase

    @State private var sessions: [ClaudeSession] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var path = NavigationPath()
    @State private var sseManager = ClaudeSessionSSEManager()
    @State private var statusFilter = "active"

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && sessions.isEmpty {
                    loadingView
                } else if let error = error, sessions.isEmpty {
                    errorView(error)
                } else {
                    sessionList
                }
            }
            .navigationTitle(filterNavigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarTitleMenu {
                Picker("Filter", selection: $statusFilter) {
                    Label("All", systemImage: "list.bullet")
                        .tag("all")
                    Label("Active", systemImage: "circle.fill")
                        .tag("active")
                    Label("Archived", systemImage: "archivebox")
                        .tag("archived")
                }
            }
            .navigationDestination(for: ClaudeDestination.self) { dest in
                switch dest {
                case .session(let session):
                    ClaudeSessionDetailView(sessionId: session.id, title: session.title)
                case .sessionById(let id):
                    ClaudeSessionDetailView(sessionId: id)
                case .newSession:
                    NewClaudeSessionView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        path.append(ClaudeDestination.newSession)
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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Restart SSE if it was dropped during background/inactive
                sseManager.ensureRunning()
                // Background-refresh to pick up any changes while app was away
                Task { await refreshSessions() }
            }
        }
        .onChange(of: path) { oldValue, newValue in
            if newValue.isEmpty && !oldValue.isEmpty {
                Task { await refreshSessions() }
            }
        }
        .onChange(of: statusFilter) { _, _ in
            sessions = []
            nextCursor = nil
            hasMore = false
            Task { await fetchSessions() }
        }
        .onChange(of: deepLink) { _, link in
            guard let link else { return }
            deepLink = nil

            // Parse /claude/{sessionId} from deep link path
            let components = link.split(separator: "/").map(String.init)
            if components.count >= 2, components[0] == "claude" {
                let sessionId = components[1]
                if let session = sessions.first(where: { $0.id == sessionId }) {
                    path.append(ClaudeDestination.session(session))
                } else {
                    path.append(ClaudeDestination.sessionById(sessionId))
                }
            } else if link == "/claude" {
                path.append(ClaudeDestination.newSession)
            }
        }
    }

    // MARK: - Helpers

    private var filterNavigationTitle: String {
        switch statusFilter {
        case "all": return "Sessions (All)"
        case "archived": return "Sessions (Archived)"
        default: return "Sessions (Active)"
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
            await refreshSessions()
        }
    }

    private func sessionButton(_ session: ClaudeSession) -> some View {
        Button {
            // Optimistically clear unread dot — the subscribe WS will confirm
            // the read state on the server when the detail view connects.
            if session.sessionState == .working || session.sessionState == .ready,
               let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session.withSessionState(.idle)
            }
            path.append(ClaudeDestination.session(session))
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
            Task { await refreshSessions() }
        }
        sseManager.start()
    }

    // MARK: - Data Fetching

    private func fetchSessions() async {
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.claude.listAll(
                status: statusFilter
            )
            sessions = response.sessions
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Background refresh — merges new data with existing sessions without
    /// showing a loading state.  Matches the web frontend's `refreshSessions`
    /// behaviour: update existing sessions, add new ones, preserve paginated
    /// sessions not in the first page, and re-sort.
    private func refreshSessions() async {
        do {
            let response = try await APIClient.shared.claude.listAll(
                status: statusFilter
            )
            let newList = response.sessions
            let newMap = Dictionary(newList.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            let prevIds = Set(sessions.map(\.id))

            // Update existing sessions with fresh data, keep paginated ones intact
            var merged = sessions.map { existing in
                newMap[existing.id] ?? existing
            }

            // Prepend any brand-new sessions not already in the list
            for session in newList where !prevIds.contains(session.id) {
                merged.insert(session, at: 0)
            }

            // Sort by lastUserActivity (or lastActivity) descending
            merged.sort { a, b in
                let dateA = a.lastUserActivity ?? a.lastActivity
                let dateB = b.lastUserActivity ?? b.lastActivity
                return dateA > dateB
            }

            sessions = merged
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
            error = nil
        } catch {
            // Silent failure for background refresh — don't overwrite visible data
            print("[ClaudeSessionListView] Background refresh failed: \(error)")
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true

        do {
            let response = try await APIClient.shared.claude.listAll(
                cursor: cursor,
                status: statusFilter
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
        // Optimistic update
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if statusFilter == "all" {
                // In "all" view, update state in-place
                withAnimation(.snappy(duration: 0.35)) {
                    sessions[index] = session.withSessionState(.archived)
                }
            } else {
                // In "active" view, remove from list
                let _ = withAnimation(.snappy(duration: 0.35)) {
                    sessions.remove(at: index)
                }
            }
        }

        do {
            try await APIClient.shared.claude.archive(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[ClaudeSessionListView] Archive failed: \(error)")
            await refreshSessions()
        }
    }

    private func unarchiveSession(_ session: ClaudeSession) async {
        // Optimistic update
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if statusFilter == "all" {
                // In "all" view, update state in-place
                withAnimation(.snappy(duration: 0.35)) {
                    sessions[index] = session.withSessionState(.idle)
                }
            } else {
                // In "archived" view, remove from list
                let _ = withAnimation(.snappy(duration: 0.35)) {
                    sessions.remove(at: index)
                }
            }
        }

        do {
            try await APIClient.shared.claude.unarchive(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[ClaudeSessionListView] Unarchive failed: \(error)")
            await refreshSessions()
        }
    }
}

// MARK: - New Session View

private struct NewClaudeSessionView: View {

    @State private var webVM = TabWebViewModel(
        route: "/claude",
        featureFlags: [
            "sessionSidebar": false,
            "sessionCreateNew": false,
        ]
    )
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            WebViewContainer(viewModel: webVM)

            if !webVM.isLoaded {
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
        .task {
            await webVM.setup(baseURL: AuthManager.shared.baseURL)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                webVM.syncTheme()
                Task { await webVM.pushAuthCookiesAndRecheck() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authTokensDidChange)) { _ in
            Task { await webVM.pushAuthCookiesAndRecheck() }
        }
        .onDisappear { }
    }
}

// MARK: - Session Row

private struct SessionRow: View {

    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 8) {
            // Collapse newlines to spaces so multi-line titles fill
            // the width (matching web's white-space:nowrap behaviour).
            Text(session.title.replacing(/\s*\n\s*/, with: " "))
                .lineLimit(1)

            Spacer()

            // Fixed-width dot column at trailing edge — always vertically aligned
            Group {
                if session.sessionState == .working || session.sessionState == .ready {
                    UnreadDot(state: session.sessionState)
                }
            }
            .frame(width: 8)

            // TimelineView re-renders every 30s so relative timestamps stay current
            // — no manual refresh token needed.
            TimelineView(.periodic(every: 30)) { context in
                Text(shortRelativeTime(session.lastUserActivity ?? session.lastActivity, now: context.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
        .opacity(session.isArchived ? 0.6 : 1.0)
    }

    private func shortRelativeTime(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}

// MARK: - Unread Dot Indicator

/// Static dot indicating unread session activity.
/// - `.working` (amber): Claude is still working
/// - `.ready` (green): Claude finished, waiting for user
private struct UnreadDot: View {

    let state: SessionState

    var body: some View {
        Circle()
            .fill(state == .working ? Color.orange : Color.green)
            .frame(width: 8, height: 8)
            .accessibilityLabel(state == .working ? "Claude is working" : "Waiting for you")
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var deepLink: String? = nil
    ClaudeSessionListView(deepLink: $deepLink)
}
