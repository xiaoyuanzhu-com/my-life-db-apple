//
//  ClaudeSessionDetailView.swift
//  MyLifeDB
//
//  WebView wrapper for viewing a single Claude session.
//  Creates its own WebPage and loads /claude/{sessionId} directly.
//  No JS bridge navigation — SwiftUI owns all navigation state.
//

import SwiftUI

struct ClaudeSessionDetailView: View {

    let sessionId: String
    let title: String?

    @State private var webVM: TabWebViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(sessionId: String, title: String? = nil) {
        self.sessionId = sessionId
        self.title = title
        self._webVM = State(initialValue: TabWebViewModel(
            route: "/claude/\(sessionId)",
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #else
        .navigationTitle(title ?? "Session")
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
    }
}
