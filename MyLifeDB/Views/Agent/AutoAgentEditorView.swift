//
//  AutoAgentEditorView.swift
//  MyLifeDB
//
//  WebView wrapper for editing a single auto-run agent definition.
//  Loads /agent/auto?edit=<name>, which the web treats as a deep-link
//  that opens the AutoAgentEditor panel for that agent. Mirrors the
//  AgentSessionDetailView structure: hidden navigation bar, custom
//  glass back button on iOS, and the same interactive-pop gesture
//  controller so swipe-to-go-back still works over the WebView.
//

import SwiftUI

struct AutoAgentEditorView: View {

    /// Agent folder name (kebab-case). Becomes the `?edit=` query value.
    let name: String

    @State private var webVM: TabWebViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(name: String) {
        self.name = name
        let route = "/agent/auto?edit=\(Self.encode(name))"
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
                    Text("Loading…")
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
        .navigationTitle(name)
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

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
