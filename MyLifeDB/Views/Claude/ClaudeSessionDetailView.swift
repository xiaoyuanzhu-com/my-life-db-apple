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
        // Disable the NavigationStack's interactive pop gesture while the web
        // frontend is showing a fullscreen preview (e.g. Estima slides).
        // This lets swipe gestures reach the iframe content instead of
        // triggering an unexpected navigation back to the session list.
        .background(
            InteractivePopGestureController(
                disabled: webVM.bridgeHandler.isFullscreenPreview
            )
        )
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
        .onDisappear {
            webVM.cancelObservation()
        }
    }
}

// MARK: - Interactive Pop Gesture Controller

#if os(iOS)
/// UIKit introspection helper that finds the hosting UINavigationController
/// and toggles its `interactivePopGestureRecognizer.isEnabled`.
///
/// SwiftUI's NavigationStack doesn't expose this gesture recognizer directly,
/// so we walk the responder chain from a dummy UIViewController to find it.
private struct InteractivePopGestureController: UIViewControllerRepresentable {

    let disabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        // Walk up to the UINavigationController (may not exist on first layout)
        vc.navigationController?.interactivePopGestureRecognizer?.isEnabled = !disabled
    }
}
#endif
