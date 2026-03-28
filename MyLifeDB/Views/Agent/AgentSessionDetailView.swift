//
//  AgentSessionDetailView.swift
//  MyLifeDB
//
//  WebView wrapper for viewing a single agent session.
//  Creates its own WebPage and loads /agent/{sessionId} directly.
//  No JS bridge navigation — SwiftUI owns all navigation state.
//

import SwiftUI

struct AgentSessionDetailView: View {

    let sessionId: String
    let title: String?

    @State private var webVM: TabWebViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(sessionId: String, title: String? = nil) {
        self.sessionId = sessionId
        self.title = title
        self._webVM = State(initialValue: TabWebViewModel(
            route: "/agent/\(sessionId)",
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
        // Hide the system navigation bar entirely to prevent the iOS 26
        // Liquid Glass material from rendering a translucent overlay on
        // top of the web content. Use a custom GlassCircleButton instead
        // (same pattern as FileViewerView). The interactive pop gesture
        // still works — InteractivePopGestureController manages it below.
        .overlay(alignment: .topLeading) {
            GlassCircleButton(systemName: "chevron.left") {
                dismiss()
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
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

// MARK: - Interactive Pop Gesture Controller

#if os(iOS)
/// UIKit introspection helper that makes the UINavigationController's
/// interactive pop gesture work over a WebView with hidden navigation bar.
///
/// Two things are needed:
/// 1. A custom gesture delegate — UIKit's default delegate blocks the pop
///    gesture when the navigation bar is hidden.
/// 2. `require(toFail:)` on the WebView's internal scroll view pan gesture —
///    otherwise the scroll view swallows edge touches before the pop gesture
///    recognizer can claim them.
///
/// Uses `viewDidAppear` + a deferred retry to walk the view hierarchy once
/// the WebView's backing scroll view exists, then sets up the dependency.
struct InteractivePopGestureController: UIViewControllerRepresentable {

    let disabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> GestureSetupController {
        let vc = GestureSetupController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: GestureSetupController, context: Context) {
        vc.isGestureDisabled = disabled
        vc.configureGesture()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var viewController: UIViewController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (viewController?.navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}

/// Custom UIViewController that sets up the pop gesture after the view
/// hierarchy is fully assembled (WebView's scroll view may not exist on
/// the first layout pass).
final class GestureSetupController: UIViewController {
    var coordinator: InteractivePopGestureController.Coordinator?
    var isGestureDisabled = false
    private var scrollViewConfigured = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        coordinator?.viewController = self
        configureGesture()
    }

    func configureGesture() {
        guard let nav = navigationController,
              let popGesture = nav.interactivePopGestureRecognizer else { return }

        popGesture.isEnabled = !isGestureDisabled

        guard !isGestureDisabled else { return }
        popGesture.delegate = coordinator

        // Walk the top view controller's view hierarchy to find the WebView's
        // internal UIScrollView and make its pan gesture yield to the pop gesture.
        if let contentView = nav.topViewController?.view {
            scrollViewConfigured = Self.requirePopGestureToFail(in: contentView, popGesture: popGesture)
        }

        // The WebView may not have laid out its scroll view yet — retry once.
        if !scrollViewConfigured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.scrollViewConfigured,
                      let nav = self.navigationController,
                      let popGesture = nav.interactivePopGestureRecognizer,
                      let contentView = nav.topViewController?.view else { return }
                self.scrollViewConfigured = Self.requirePopGestureToFail(
                    in: contentView, popGesture: popGesture
                )
            }
        }
    }

    /// Recursively find UIScrollViews and set `require(toFail:)` on their
    /// pan gesture recognizer so the navigation pop gesture takes priority.
    @discardableResult
    private static func requirePopGestureToFail(
        in view: UIView, popGesture: UIGestureRecognizer
    ) -> Bool {
        var found = false
        if let scrollView = view as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: popGesture)
            found = true
        }
        for subview in view.subviews {
            if requirePopGestureToFail(in: subview, popGesture: popGesture) {
                found = true
            }
        }
        return found
    }
}
#endif
