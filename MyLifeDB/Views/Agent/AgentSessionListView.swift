//
//  AgentSessionListView.swift
//  MyLifeDB
//
//  Native session list for the Agent tab.
//  Fetches sessions from the API and displays them in a SwiftUI List.
//  Tapping a session pushes a detail view with its own dedicated WebView.
//

import SwiftUI

// MARK: - Navigation Destination

enum AgentDestination: Hashable {
    case session(AgentSession)
    case sessionById(String)
    case newSession
    case createAgent
}

/// Top-level segment selection for the Agent tab.
/// Mirrors the web's two-tab segmented control: "Sessions ▾ | Auto".
enum AgentSection: Hashable {
    case sessions
    case auto
}

struct AgentSessionListView: View {

    @Binding var deepLink: String?

    @Environment(\.scenePhase) private var scenePhase

    @State private var sessions: [AgentSession] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var hasMore = false
    @State private var nextCursor: String?
    @State private var path = NavigationPath()
    @State private var sseManager = AgentSessionSSEManager()
    @State private var statusFilter = "active"
    @State private var section: AgentSection = .sessions

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if section == .auto {
                    AutoAgentListView(path: $path)
                } else if isLoading && sessions.isEmpty {
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
            .navigationDestination(for: AgentDestination.self) { dest in
                switch dest {
                case .session(let session):
                    AgentSessionDetailView(sessionId: session.id, title: session.title)
                case .sessionById(let id):
                    AgentSessionDetailView(sessionId: id)
                case .newSession:
                    NewAgentSessionView()
                case .createAgent:
                    NewAgentSessionView(seed: "/create-agent")
                }
            }
            .navigationDestination(for: AutoAgentDestination.self) { dest in
                switch dest {
                case .editor(let name):
                    AutoAgentEditorView(name: name)
                case .create:
                    NewAgentSessionView(seed: "/create-agent")
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SectionToggle(section: $section, statusFilter: $statusFilter)
                }
                if section == .sessions {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            path.append(AgentDestination.newSession)
                        } label: {
                            Image(systemName: "plus")
                        }
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
            sseManager.onSessionUpdated = nil
            sseManager.stop()
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

            // Parse /agent/{sessionId} from deep link path
            let components = link.split(separator: "/").map(String.init)
            if components.count >= 2, components[0] == "agent" {
                let sessionId = components[1]
                if let session = sessions.first(where: { $0.id == sessionId }) {
                    path.append(AgentDestination.session(session))
                } else {
                    path.append(AgentDestination.sessionById(sessionId))
                }
            } else if link == "/agent" {
                path.append(AgentDestination.newSession)
            }
        }
    }

    // MARK: - Session List

    private var groupedSessions: [(title: String, sessions: [AgentSession])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday),
              let startOfMonth = calendar.date(byAdding: .month, value: -1, to: startOfToday)
        else { return [("All", sessions)] }

        var today: [AgentSession] = []
        var yesterday: [AgentSession] = []
        var pastWeek: [AgentSession] = []
        var pastMonth: [AgentSession] = []
        var earlier: [AgentSession] = []

        for session in sessions {
            let date = (session.lastUserActivity ?? session.lastActivity).asDate
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

        var result: [(String, [AgentSession])] = []
        if !today.isEmpty { result.append((String(localized: "Today"), today)) }
        if !yesterday.isEmpty { result.append((String(localized: "Yesterday"), yesterday)) }
        if !pastWeek.isEmpty { result.append((String(localized: "Past Week"), pastWeek)) }
        if !pastMonth.isEmpty { result.append((String(localized: "Past Month"), pastMonth)) }
        if !earlier.isEmpty { result.append((String(localized: "Earlier"), earlier)) }
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

    private func sessionButton(_ session: AgentSession) -> some View {
        Button {
            // Optimistically clear unread dot — the subscribe WS will confirm
            // the read state on the server when the detail view connects.
            if session.sessionState == .working || session.sessionState == .unread,
               let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session.withSessionState(.idle)
            }
            path.append(AgentDestination.session(session))
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
            let response = try await APIClient.shared.agent.listAll(
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
            let response = try await APIClient.shared.agent.listAll(
                status: statusFilter
            )
            let newList = response.sessions
            let newMap = Dictionary(newList.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            let freshIds = Set(newList.map(\.id))
            let prevIds = Set(sessions.map(\.id))

            // Update existing sessions with fresh data, keep paginated ones intact
            var merged = sessions.map { existing in
                newMap[existing.id] ?? existing
            }

            // Prepend any brand-new sessions not already in the list
            for session in newList where !prevIds.contains(session.id) {
                merged.insert(session, at: 0)
            }

            // Remove sessions that should have appeared in the first page but
            // didn't (e.g. archived/deleted on another device).  Only drop
            // sessions whose activity date is recent enough to fall within the
            // first page — truly paginated older sessions are left alone.
            if let oldestFresh = newList.last {
                let cutoff = oldestFresh.lastUserActivity ?? oldestFresh.lastActivity
                merged.removeAll { session in
                    let ms = session.lastUserActivity ?? session.lastActivity
                    return !freshIds.contains(session.id) && ms >= cutoff
                }
            }

            // Sort by lastUserActivity (or lastActivity) descending
            merged.sort { a, b in
                let msA = a.lastUserActivity ?? a.lastActivity
                let msB = b.lastUserActivity ?? b.lastActivity
                return msA > msB
            }

            withAnimation(.snappy(duration: 0.35)) {
                sessions = merged
            }
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
            error = nil
        } catch {
            // Silent failure for background refresh — don't overwrite visible data
            print("[AgentSessionListView] Background refresh failed: \(error)")
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true

        do {
            let response = try await APIClient.shared.agent.listAll(
                cursor: cursor,
                status: statusFilter
            )
            sessions.append(contentsOf: response.sessions)
            hasMore = response.pagination.hasMore
            nextCursor = response.pagination.nextCursor
        } catch {
            // Silently fail on load-more; user can scroll up and try again
            print("[AgentSessionListView] Load more failed: \(error)")
        }

        isLoading = false
    }

    // MARK: - Archive / Unarchive

    private func archiveSession(_ session: AgentSession) async {
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
            try await APIClient.shared.agent.archive(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[AgentSessionListView] Archive failed: \(error)")
            await refreshSessions()
        }
    }

    private func unarchiveSession(_ session: AgentSession) async {
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
            try await APIClient.shared.agent.unarchive(sessionId: session.id)
        } catch {
            // Revert on failure
            print("[AgentSessionListView] Unarchive failed: \(error)")
            await refreshSessions()
        }
    }
}

// MARK: - New Session View

private struct NewAgentSessionView: View {

    /// Optional seed appended as `?seed=<value>` so the web composer pre-fills.
    /// e.g. `/create-agent` opens the new-session view with the create-agent
    /// skill already staged in the input.
    let seed: String?

    @State private var webVM: TabWebViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(seed: String? = nil) {
        self.seed = seed
        let route: String
        if let seed, !seed.isEmpty {
            let encoded = seed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? seed
            route = "/agent?seed=\(encoded)"
        } else {
            route = "/agent"
        }
        self._webVM = State(initialValue: TabWebViewModel(
            route: route,
            featureFlags: [
                "sessionSidebar": false,
                "sessionCreateNew": false,
            ]
        ))
    }

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
        .overlay(alignment: .topLeading) {
            GlassCircleButton(systemName: "chevron.left") {
                dismiss()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(
            InteractivePopGestureController(
                disabled: webVM.bridgeHandler.isFullscreenPreview
            )
        )
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
            Task { await webVM.pushAuthCookies() }
        }
        .onChange(of: webVM.bridgeHandler.isRequestingGoBack) { _, requesting in
            if requesting { dismiss() }
        }
        .onDisappear {
            webVM.cancelObservation()
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {

    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            // Collapse newlines to spaces so multi-line titles fill
            // the width (matching web's white-space:nowrap behaviour).
            Text(session.title.replacing(/\s*\n\s*/, with: " "))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if session.sessionState == .working || session.sessionState == .unread {
                UnreadDot(state: session.sessionState)
            }

            // TimelineView re-renders every 30s so relative timestamps stay current
            // — no manual refresh token needed.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(shortRelativeTime((session.lastUserActivity ?? session.lastActivity).asDate, now: context.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
        .opacity(session.isArchived ? 0.6 : 1.0)
    }

    private func shortRelativeTime(_ date: Date, now: Date) -> String {
        // Note: compact numeric abbreviations (5s, 3m, 2h, 4d) are intentionally
        // kept locale-independent for readability in a cramped list cell.
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

/// Static dot indicating session activity.
/// - `.working` (amber): Agent is still working
/// - `.unread` (green): unread result (completed turn) or pending permission
private struct UnreadDot: View {

    let state: SessionState

    var body: some View {
        Circle()
            .fill(state == .working ? Color.orange : Color.green)
            .frame(width: 8, height: 8)
            .accessibilityLabel(state == .working ? String(localized: "Agent is working") : String(localized: "Unread results"))
    }
}

// MARK: - Section Toggle

/// Segmented "Sessions ▾ | Auto" pill placed in the navigation bar's
/// principal slot. Mirrors the web's two-tab header (bg-muted/50 p-0.5
/// pill with two button-style tabs).
///
/// On the active "Sessions" tab a Menu surfaces the status filter
/// (All / Active / Archived) — replacing the previous toolbarTitleMenu.
private struct SectionToggle: View {

    @Binding var section: AgentSection
    @Binding var statusFilter: String

    var body: some View {
        HStack(spacing: 2) {
            sessionsTab
            autoTab
        }
        .padding(2)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
    }

    @ViewBuilder
    private var sessionsTab: some View {
        if section == .sessions {
            // Active — tap to open status-filter menu.
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
                tabLabel(text: sessionsTitle, isActive: true, showChevron: true)
            }
        } else {
            // Inactive — tap to switch to sessions.
            Button {
                section = .sessions
            } label: {
                tabLabel(text: sessionsTitle, isActive: false, showChevron: false)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var autoTab: some View {
        Button {
            section = .auto
        } label: {
            tabLabel(text: String(localized: "Auto"), isActive: section == .auto, showChevron: false)
        }
        .buttonStyle(.plain)
    }

    private var sessionsTitle: String {
        switch statusFilter {
        case "all": return String(localized: "All")
        case "archived": return String(localized: "Archived")
        default: return String(localized: "Sessions")
        }
    }

    private func tabLabel(text: String, isActive: Bool, showChevron: Bool) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isActive ? Color.platformBackground : Color.clear)
                .shadow(color: isActive ? Color.black.opacity(0.06) : .clear, radius: 1, y: 1)
        )
        .contentShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var deepLink: String? = nil
    AgentSessionListView(deepLink: $deepLink)
}
