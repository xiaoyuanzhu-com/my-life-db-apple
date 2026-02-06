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
                }
            }
            .animation(.default, value: authManager.state)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                authManager.handleForeground()
            }
        }
    }
}
