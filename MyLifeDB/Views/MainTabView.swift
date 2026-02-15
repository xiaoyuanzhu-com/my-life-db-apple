//
//  MainTabView.swift
//  MyLifeDB
//
//  Root navigation view with four tabs:
//  - Inbox: Native SwiftUI inbox feed
//  - Library: Native SwiftUI file browser
//  - Claude: Native session list → WebView detail per session
//  - Me: Native SwiftUI (profile and settings)
//
//  Claude web tab owns an independent WebPage instance via TabWebViewModel.
//  Uses native SwiftUI TabView on iOS/iPadOS and NavigationSplitView on macOS.
//

import SwiftUI

// MARK: - Tab Definition

enum AppTab: String, CaseIterable {
    case inbox = "Inbox"
    case library = "Library"
    case claude = "Claude"
    case me = "Me"

    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .library: return "folder"
        case .claude: return "bubble.left.and.bubble.right"
        case .me: return "person.circle"
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    /// Deep link path passed from MyLifeDBApp.
    @Binding var deepLinkPath: String?

    @State private var selectedTab: AppTab = .inbox
    @State private var claudeVM = TabWebViewModel(route: "/claude")

    @Environment(\.scenePhase) private var scenePhase

    private var allViewModels: [TabWebViewModel] { [claudeVM] }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - iOS Layout

    #if !os(macOS)
    private var iOSLayout: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.inbox.rawValue, systemImage: AppTab.inbox.icon, value: .inbox) {
                NativeInboxView()
            }
            Tab(AppTab.library.rawValue, systemImage: AppTab.library.icon, value: .library) {
                NativeLibraryBrowserView()
            }
            Tab(AppTab.claude.rawValue, systemImage: AppTab.claude.icon, value: .claude) {
                ClaudeSessionListView(claudeVM: claudeVM)
            }
            Tab(AppTab.me.rawValue, systemImage: AppTab.me.icon, value: .me) {
                MeView()
            }
        }
        .modifier(SharedModifiers(
            allViewModels: allViewModels,
            selectedTab: $selectedTab,
            deepLinkPath: $deepLinkPath,
            scenePhase: scenePhase
        ))
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedTab {
            case .inbox:
                NativeInboxView()
            case .library:
                NativeLibraryBrowserView()
            case .claude:
                ClaudeSessionListView(claudeVM: claudeVM)
            case .me:
                MeView()
            }
        }
        .modifier(SharedModifiers(
            allViewModels: allViewModels,
            selectedTab: $selectedTab,
            deepLinkPath: $deepLinkPath,
            scenePhase: scenePhase
        ))
    }
    #endif

    // MARK: - Deep Link → Tab Mapping

    private func viewModel(for path: String) -> (AppTab, TabWebViewModel)? {
        if path.hasPrefix("/claude") {
            return (.claude, claudeVM)
        }
        // Inbox and Library are now native and don't use WebView models
        return nil
    }
}

// MARK: - Shared Modifiers

/// Extracted as a ViewModifier so iOS and macOS layouts share the same
/// setup, scenePhase, deep link, and notification handling.
private struct SharedModifiers: ViewModifier {
    let allViewModels: [TabWebViewModel]
    @Binding var selectedTab: AppTab
    @Binding var deepLinkPath: String?
    let scenePhase: ScenePhase

    func body(content: Content) -> some View {
        content
            .task {
                let baseURL = AuthManager.shared.baseURL
                for vm in allViewModels {
                    await vm.setup(baseURL: baseURL)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    for vm in allViewModels {
                        vm.syncTheme()
                    }
                    Task {
                        for vm in allViewModels {
                            await vm.updateAuthCookies()
                        }
                    }
                }
            }
            .onChange(of: deepLinkPath) { _, path in
                guard let path else { return }
                handleDeepLink(path)
                deepLinkPath = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .webViewShouldReload)) { notification in
                guard let newURL = notification.object as? URL else { return }
                Task {
                    for vm in allViewModels {
                        await vm.teardownAndReload(baseURL: newURL)
                    }
                }
            }
    }

    private func handleDeepLink(_ path: String) {
        if path == "/" || path.hasPrefix("/inbox") {
            selectedTab = .inbox
            // Inbox is now native; no WebView navigation needed
            return
        } else if path.hasPrefix("/library") || path.hasPrefix("/file") {
            selectedTab = .library
            // Library is now native; deep path navigation handled by NativeLibraryBrowserView
            return
        } else if path.hasPrefix("/claude") {
            selectedTab = .claude
        } else if path.hasPrefix("/settings") || path.hasPrefix("/people") {
            selectedTab = .me
            return
        }

        // Navigate within the selected tab's WebView if it's a sub-path
        if let vm = allViewModels.first(where: { path.hasPrefix($0.route) }) {
            vm.navigateTo(path: path)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var deepLink: String? = nil
    MainTabView(deepLinkPath: $deepLink)
}
