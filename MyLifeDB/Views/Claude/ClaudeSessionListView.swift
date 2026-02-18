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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                ToolbarItem(placement: .principal) {
                    Menu {
                        Picker("Filter", selection: $statusFilter) {
                            Label("All", systemImage: "list.bullet")
                                .tag("all")
                            Label("Active", systemImage: "circle.fill")
                                .tag("active")
                            Label("Archived", systemImage: "archivebox")
                                .tag("archived")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Sessions")
                                .fontWeight(.semibold)
                            Text("(\(filterDisplayName))")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.headline)
                        .foregroundStyle(.primary)
                    }
                }
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
        .onDisappear {
            sseManager.stop()
        }
        .onChange(of: path) { oldValue, newValue in
            if newValue.isEmpty && !oldValue.isEmpty {
                Task { await refresh() }
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

    private var filterDisplayName: String {
        switch statusFilter {
        case "all": return "All"
        case "archived": return "Archived"
        default: return "Active"
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

    private func refresh() async {
        nextCursor = nil
        hasMore = false

        do {
            let response = try await APIClient.shared.claude.listAll(
                status: statusFilter
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
                // In "all" view, update status in-place
                withAnimation(.snappy(duration: 0.35)) {
                    sessions[index] = session.withStatus("archived")
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
            await refresh()
        }
    }

    private func unarchiveSession(_ session: ClaudeSession) async {
        // Optimistic update
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            if statusFilter == "all" {
                // In "all" view, update status in-place
                withAnimation(.snappy(duration: 0.35)) {
                    sessions[index] = session.withStatus("active")
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
            await refresh()
        }
    }
}

// MARK: - New Session View

private struct NewClaudeSessionView: View {

    @State private var webVM = TabWebViewModel(route: "/claude")
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
        HStack {
            Text(session.title)
                .lineLimit(1)

            Spacer()

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
    @Previewable @State var deepLink: String? = nil
    ClaudeSessionListView(deepLink: $deepLink)
}
