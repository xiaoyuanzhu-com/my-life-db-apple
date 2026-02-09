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

                case .authenticated, .noAuthRequired:
                    MainTabView()
                        .task {
                            // Initialize the shared WebView with the backend URL.
                            // Auth cookies are injected before the SPA loads so the
                            // web frontend's cookie-based auth works transparently.
                            await WebViewManager.shared.setup(
                                baseURL: authManager.baseURL
                            )

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

                // Sync theme with native appearance when returning to foreground
                Task { @MainActor in
                    WebViewManager.shared.syncTheme()
                }

                // Update auth cookies in case they were refreshed in background
                Task {
                    await WebViewManager.shared.updateAuthCookies()
                }

                // Trigger data collection sync (throttled internally)
                SyncManager.shared.sync()
            }
        }
    }

    // MARK: - Deep Linking

    /// Handle deep links (e.g., mylifedb://inbox/12345, mylifedb://library/path/to/file).
    @MainActor
    private func handleDeepLink(_ url: URL) {
        // Only handle our custom scheme
        guard url.scheme == "mylifedb" else { return }

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

        WebViewManager.shared.navigateTo(path: path)
    }
}
