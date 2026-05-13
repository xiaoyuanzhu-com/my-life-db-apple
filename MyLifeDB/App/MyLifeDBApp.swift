//
//  MyLifeDBApp.swift
//  MyLifeDB
//
//  Created by Li Zhao on 2025/12/9.
//

import SwiftUI
import SwiftData

@main
struct MyLifeDBApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Local app state models (not backend data)
            // e.g., RecentFolder.self, PendingMessage.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var authManager = AuthManager.shared
    @State private var deepLinkPath: String?
    @State private var refreshID = UUID()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch authManager.state {
                case .unknown, .checking:
                    ProgressView("Connecting...")
                        .task {
                            await authManager.checkAuth()
                        }

                case .unauthenticated:
                    LoginView()

                case .provisioning:
                    ProvisioningView()

                case .authenticated:
                    MainTabView(deepLinkPath: $deepLinkPath)
                        .id(refreshID)
                        .task {
                            // Sync API base URL to shared UserDefaults so the
                            // Share Extension can access it via App Group.
                            syncSharedDefaults()

                            // Drain any shares that the Share Extension
                            // staged while the app was offline. This is
                            // the safety net for the deeplink handoff —
                            // shares always get uploaded once the user
                            // opens the app, even if `open(_:)` failed.
                            await ShareQueueDrainer.drainAll()

                            // Register background sync task
                            #if os(iOS)
                            SyncManager.shared.registerBackgroundTask()
                            SyncManager.shared.scheduleBackgroundSync()
                            #endif
                        }
                }
            }
            .animation(.default, value: authManager.state)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                // Universal Links land here. The Share Extension hands off
                // via https://my.xiaoyuanzhu.com/ios-share/<uuid>, which iOS
                // routes to this callback (vs opening Safari) because the
                // domain's AASA file declares that path for our App ID.
                if let url = activity.webpageURL {
                    handleDeepLink(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .webViewShouldReload)) { _ in
                refreshID = UUID()
            }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("[Scene] phase: \(oldPhase) -> \(newPhase)")
            if newPhase == .active {
                authManager.handleForeground()

                // Background sync and share-drain are only meaningful when
                // we have a session. Firing them while unauthenticated (or
                // mid-OAuth bounce) causes useless 401s and contributes to
                // race-prone state flips.
                guard authManager.isAuthenticated else { return }
                SyncManager.shared.sync()
                Task { await ShareQueueDrainer.drainAll() }
            }
        }
    }

    // MARK: - Shared Defaults Sync

    /// Sync the API base URL to the shared UserDefaults suite so the
    /// Share Extension (which runs in a separate process) can read it.
    private func syncSharedDefaults() {
        let url = UserDefaults.standard.string(forKey: "apiBaseURL")
            ?? SharedConstants.defaultBaseURL
        SharedConstants.sharedDefaults.set(url, forKey: SharedConstants.apiBaseURLKey)
    }

    // MARK: - Deep Linking

    /// Handle incoming deep links and universal links.
    ///
    /// Supported inputs:
    ///   - `mylifedb://oauth/callback?session_token=...` — OAuth completion
    ///   - `mylifedb://<host>[/path]` — SPA routes (library, file/..., etc.)
    ///   - `https://my.xiaoyuanzhu.com/ios-share/<uuid>` — Share Extension
    ///     handoff via Universal Links. The domain's AASA file declares
    ///     this path; iOS routes the URL here instead of Safari.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        print("[DeepLink] received: \(url.absoluteString)")

        // Universal link from the Share Extension
        if url.scheme == "https",
           url.host == "my.xiaoyuanzhu.com",
           url.path.hasPrefix("/ios-share/") {
            let id = String(url.path.dropFirst("/ios-share/".count))
            guard !id.isEmpty else { return }
            Task { await ShareQueueDrainer.drain(id: id) }
            return
        }

        // Custom-scheme deep links — parse via URLComponents for robustness.
        // On iOS 17+ URL.host / URL.path are deprecated and can return
        // unexpected values for custom-scheme URLs; URLComponents stays
        // accurate across versions.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              scheme.caseInsensitiveCompare("mylifedb") == .orderedSame else {
            print("[DeepLink] not a mylifedb URL, ignoring")
            return
        }

        let host = components.host ?? ""
        let path = components.path
        print("[DeepLink] mylifedb host=\(host) path=\(path)")

        // Handle OAuth callback
        if host == "oauth" && path == "/callback" {
            handleOAuthCallback(components: components)
            return
        }

        // The host + path form the web route
        // e.g., mylifedb://library → /library
        //        mylifedb://library/foo → /library/foo
        let routePath = host.isEmpty ? path : "/\(host)\(path)"
        guard !routePath.isEmpty else { return }
        deepLinkPath = routePath
    }

    @MainActor
    private func handleOAuthCallback(components: URLComponents) {
        let queryItems = components.queryItems ?? []
        guard let sessionToken = queryItems.first(where: { $0.name == "session_token" })?.value,
              !sessionToken.isEmpty else {
            print("[OAuthCallback] no session_token in queryItems=\(queryItems)")
            return
        }
        print("[OAuthCallback] received session_token (len=\(sessionToken.count)) — completing auth")
        authManager.handleOAuthCompletion(sessionToken: sessionToken)
    }
}
