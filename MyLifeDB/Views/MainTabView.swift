//
//  MainTabView.swift
//  MyLifeDB
//
//  Root navigation view with four tabs:
//  - Inbox: Native SwiftUI inbox feed
//  - Library: Native SwiftUI file browser
//  - Claude: Native session list → dedicated WebView per session detail
//  - Me: Native SwiftUI (profile and settings)
//
//  Each Claude session detail creates its own WebPage instance.
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

    @Namespace private var previewNamespace
    @State private var selectedTab: AppTab = .inbox
    @State private var filePreview: FilePreviewDestination?
    @State private var claudeDeepLink: String?

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    /// Shared modifiers for file preview presentation.
    private func withFilePreview<V: View>(_ content: V) -> some View {
        content
            #if os(macOS)
            .sheet(item: $filePreview) { preview in
                fileViewerView(for: preview)
                    .presentationBackground(.black)
                    .frame(minWidth: 600, minHeight: 500)
            }
            #else
            .fullScreenCover(item: $filePreview) { preview in
                fileViewerView(for: preview)
                    .presentationBackground(.black)
                    .navigationTransition(.zoom(sourceID: preview.path, in: previewNamespace))
            }
            #endif
            .environment(\.openFilePreview) { path, name, file, pagerContext in
                filePreview = FilePreviewDestination(path: path, name: name, file: file, pagerContext: pagerContext)
            }
            .environment(\.previewNamespace, previewNamespace)
    }

    // MARK: - iOS Layout

    #if !os(macOS)
    private var iOSLayout: some View {
        withFilePreview(
            TabView(selection: $selectedTab) {
                Tab(AppTab.inbox.rawValue, systemImage: AppTab.inbox.icon, value: .inbox) {
                    NativeInboxView()
                }
                Tab(AppTab.library.rawValue, systemImage: AppTab.library.icon, value: .library) {
                    NativeLibraryBrowserView()
                }
                Tab(AppTab.claude.rawValue, systemImage: AppTab.claude.icon, value: .claude) {
                    ClaudeSessionListView(deepLink: $claudeDeepLink)
                }
                Tab(AppTab.me.rawValue, systemImage: AppTab.me.icon, value: .me) {
                    MeView()
                }
            }
            .modifier(SharedModifiers(
                selectedTab: $selectedTab,
                deepLinkPath: $deepLinkPath,
                claudeDeepLink: $claudeDeepLink
            ))
        )
    }
    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        withFilePreview(
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
                    ClaudeSessionListView(deepLink: $claudeDeepLink)
                case .me:
                    MeView()
                }
            }
            .modifier(SharedModifiers(
                selectedTab: $selectedTab,
                deepLinkPath: $deepLinkPath,
                claudeDeepLink: $claudeDeepLink
            ))
        )
    }
    #endif

    // MARK: - File Viewer

    @ViewBuilder
    private func fileViewerView(for preview: FilePreviewDestination) -> some View {
        let dismiss = { filePreview = nil }
        if let context = preview.pagerContext {
            FilePreviewPagerView(context: context, onDismiss: dismiss)
        } else if let file = preview.file {
            FileViewerView(file: file, onDismiss: dismiss)
        } else {
            FileViewerView(filePath: preview.path, fileName: preview.name, onDismiss: dismiss)
        }
    }
}

// MARK: - Shared Modifiers

/// Extracted as a ViewModifier so iOS and macOS layouts share the same
/// deep link and notification handling.
private struct SharedModifiers: ViewModifier {
    @Binding var selectedTab: AppTab
    @Binding var deepLinkPath: String?
    @Binding var claudeDeepLink: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: deepLinkPath) { _, path in
                guard let path else { return }
                handleDeepLink(path)
                deepLinkPath = nil
            }
    }

    private func handleDeepLink(_ path: String) {
        if path == "/" || path.hasPrefix("/inbox") {
            selectedTab = .inbox
        } else if path.hasPrefix("/library") || path.hasPrefix("/file") {
            selectedTab = .library
        } else if path.hasPrefix("/claude") {
            selectedTab = .claude
            claudeDeepLink = path
        } else if path.hasPrefix("/settings") || path.hasPrefix("/people") {
            selectedTab = .me
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var deepLink: String? = nil
    MainTabView(deepLinkPath: $deepLink)
}
