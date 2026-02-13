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

                case .authenticated:
                    MainTabView(deepLinkPath: $deepLinkPath)
                        .task {
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
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                authManager.handleForeground()

                // Trigger data collection sync (throttled internally)
                SyncManager.shared.sync()
            }
        }
    }

    // MARK: - Deep Linking

    /// Handle deep links (e.g., mylifedb://oauth/callback?access_token=..., mylifedb://inbox/12345).
    @MainActor
    private func handleDeepLink(_ url: URL) {
        // Only handle our custom scheme
        guard url.scheme == "mylifedb" else { return }

        // Handle OAuth callback
        if url.host == "oauth" && url.path == "/callback" {
            handleOAuthCallback(url)
            return
        }

        // The host + path form the web route
        // e.g., mylifedb://inbox/123 → /inbox/123
        //        mylifedb://library → /library
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

        guard let accessToken = queryItems.first(where: { $0.name == "access_token" })?.value else {
            return
        }

        let refreshToken = queryItems.first(where: { $0.name == "refresh_token" })?.value
        authManager.handleOAuthCompletion(accessToken: accessToken, refreshToken: refreshToken)
    }
}
