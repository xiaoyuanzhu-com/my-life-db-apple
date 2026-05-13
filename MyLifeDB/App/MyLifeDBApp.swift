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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                authManager.handleForeground()

                // Trigger data collection sync (throttled internally)
                SyncManager.shared.sync()

                // Pick up any shares the extension staged while we were
                // backgrounded. Cheap when the queue is empty.
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
        // Universal link from the Share Extension
        if url.scheme == "https",
           url.host == "my.xiaoyuanzhu.com",
           url.path.hasPrefix("/ios-share/") {
            let id = String(url.path.dropFirst("/ios-share/".count))
            guard !id.isEmpty else { return }
            Task { await ShareQueueDrainer.drain(id: id) }
            return
        }

        // Custom-scheme deep links below
        guard url.scheme == "mylifedb" else { return }

        // Handle OAuth callback
        if url.host == "oauth" && url.path == "/callback" {
            handleOAuthCallback(url)
            return
        }

        // The host + path form the web route
        // e.g., mylifedb://library → /library
        //        mylifedb://library/foo → /library/foo
        let path: String
        if let host = url.host {
            path = "/\(host)\(url.path)"
        } else {
            path = url.path
        }

        guard !path.isEmpty else { return }

        // Pass to MainTabView via binding
        deepLinkPath = path
    }

    @MainActor
    private func handleOAuthCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let queryItems = components.queryItems ?? []

        guard let sessionToken = queryItems.first(where: { $0.name == "session_token" })?.value else {
            return
        }

        authManager.handleOAuthCompletion(sessionToken: sessionToken)
    }
}
