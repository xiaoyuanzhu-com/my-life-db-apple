//
//  MainTabView.swift
//  MyLifeDB
//
//  Root navigation view with four tabs:
//  - Inbox: WebView (web frontend "/")
//  - Library: WebView (web frontend "/library")
//  - Claude: WebView (web frontend "/claude")
//  - Me: Native SwiftUI (profile and settings)
//
//  Architecture:
//  - iOS/iPadOS: ZStack with persistent WebView + CustomTabBar
//    (standard TabView would recreate child views on switch, detaching the WebView)
//  - macOS: NavigationSplitView sidebar + WebView or native MeView in detail
//

import SwiftUI

// MARK: - Tab Definition

enum Tab: String, CaseIterable {
    case inbox = "Inbox"
    case library = "Library"
    case claude = "Claude"
    case me = "Me"

    /// SF Symbol name (outline variant).
    var icon: String {
        switch self {
        case .inbox: return "tray"
        case .library: return "folder"
        case .claude: return "bubble.left.and.bubble.right"
        case .me: return "person.circle"
        }
    }

    /// SF Symbol name (filled variant, for selected state).
    var iconFilled: String {
        switch self {
        case .inbox: return "tray.fill"
        case .library: return "folder.fill"
        case .claude: return "bubble.left.and.bubble.right.fill"
        case .me: return "person.circle.fill"
        }
    }

    /// The web frontend route this tab navigates to, or nil for native-only tabs.
    var webRoute: String? {
        switch self {
        case .inbox: return "/"
        case .library: return "/library"
        case .claude: return "/claude"
        case .me: return nil
        }
    }

    /// Whether this tab renders via WebView (vs native SwiftUI).
    var isWebView: Bool { webRoute != nil }
}

// MARK: - MainTabView

struct MainTabView: View {
    @State private var selectedTab: Tab = .inbox

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
        ZStack {
            // The shared WebView is always present behind everything.
            // When the Me tab is selected, it's hidden (opacity 0) but stays alive
            // so the SPA state (React, query cache, scroll position) is preserved.
            WebViewContainer()
                .ignoresSafeArea(edges: .bottom) // CustomTabBar handles bottom safe area
                .opacity(selectedTab.isWebView ? 1 : 0)

            // Native MeView overlays when the Me tab is selected.
            // MeView has its own NavigationStack, so no wrapper needed.
            if selectedTab == .me {
                MeView()
                    .transition(.identity)
            }

            // Loading overlay while the WebView is booting up.
            if selectedTab.isWebView && !WebViewManager.shared.isLoaded {
                loadingOverlay
            }

            // Error overlay if the WebView failed to load.
            if selectedTab.isWebView, let error = WebViewManager.shared.loadError {
                errorOverlay(error)
            }
        }
        .safeAreaInset(edge: .bottom) {
            CustomTabBar(selectedTab: $selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            if let route = newTab.webRoute {
                WebViewManager.shared.navigateTo(path: route)
            }
        }
        .onAppear {
            // Set up the bridge callback: when the web frontend navigates,
            // sync the native tab selection.
            WebViewManager.shared.bridgeHandler.onNavigate = { path in
                syncTabFromWebPath(path)
            }
        }
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if selectedTab == .me {
                MeView()
            } else {
                ZStack {
                    WebViewContainer()

                    if !WebViewManager.shared.isLoaded {
                        loadingOverlay
                    }

                    if let error = WebViewManager.shared.loadError {
                        errorOverlay(error)
                    }
                }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if let route = newTab.webRoute {
                WebViewManager.shared.navigateTo(path: route)
            }
        }
        .onAppear {
            WebViewManager.shared.bridgeHandler.onNavigate = { path in
                syncTabFromWebPath(path)
            }
        }
    }
    #endif

    // MARK: - Loading & Error Overlays

    private var loadingOverlay: some View {
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

    private func errorOverlay(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Unable to Connect")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                WebViewManager.shared.reload()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformBackground)
    }

    // MARK: - Tab ↔ Web Path Sync

    /// Map a web frontend path back to the correct native tab.
    private func syncTabFromWebPath(_ path: String) {
        if path == "/" || path.hasPrefix("/inbox") {
            selectedTab = .inbox
        } else if path.hasPrefix("/library") || path.hasPrefix("/file") {
            selectedTab = .library
        } else if path.hasPrefix("/claude") {
            selectedTab = .claude
        } else if path.hasPrefix("/settings") || path.hasPrefix("/people") {
            // Settings and People are accessible from the web but map to Me tab
            selectedTab = .me
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
}
