//
//  MainTabView.swift
//  MyLifeDB
//
//  Root navigation view with three tabs:
//  - Data: Native SwiftUI file browser
//  - Agent: Native session list -> dedicated WebView per session detail
//  - Me: Native SwiftUI (profile and settings)
//
//  Each agent session detail creates its own WebPage instance.
//  Uses native SwiftUI TabView on iOS/iPadOS and NavigationSplitView on macOS.
//

import SwiftUI

// MARK: - Tab Definition

enum AppTab: String, CaseIterable {
    case data = "Data"
    case explore = "Explore"
    case agent = "Agent"
    case me = "Me"

    var icon: String {
        switch self {
        case .data: return "folder"
        case .explore: return "safari"
        case .agent: return "bubble.left.and.bubble.right"
        case .me: return "person.circle"
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    /// Deep link path passed from MyLifeDBApp.
    @Binding var deepLinkPath: String?

    @Namespace private var previewNamespace
    @State private var selectedTab: AppTab = .data
    @State private var filePreview: FilePreviewDestination?
    @State private var agentDeepLink: String?

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
                Tab(AppTab.data.rawValue, systemImage: AppTab.data.icon, value: .data) {
                    NativeLibraryBrowserView()
                }
                Tab(AppTab.explore.rawValue, systemImage: AppTab.explore.icon, value: .explore) {
                    ExploreView()
                }
                Tab(AppTab.agent.rawValue, systemImage: AppTab.agent.icon, value: .agent) {
                    AgentSessionListView(deepLink: $agentDeepLink)
                }
                Tab(AppTab.me.rawValue, systemImage: AppTab.me.icon, value: .me) {
                    MeView()
                }
            }
            .modifier(SharedModifiers(
                selectedTab: $selectedTab,
                deepLinkPath: $deepLinkPath,
                agentDeepLink: $agentDeepLink
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
                case .data:
                    NativeLibraryBrowserView()
                case .explore:
                    ExploreView()
                case .agent:
                    AgentSessionListView(deepLink: $agentDeepLink)
                case .me:
                    MeView()
                }
            }
            .modifier(SharedModifiers(
                selectedTab: $selectedTab,
                deepLinkPath: $deepLinkPath,
                agentDeepLink: $agentDeepLink
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
        } else {
            let isMedia = preview.file?.isImage == true || preview.file?.isVideo == true
            FilePreviewOverlay(
                filePath: preview.path,
                fileName: preview.name,
                file: preview.file,
                isMedia: isMedia,
                onDismiss: dismiss
            ) { toggleToolbar in
                if let file = preview.file {
                    FileViewerView(file: file, onSingleTap: isMedia ? toggleToolbar : nil)
                } else {
                    FileViewerView(filePath: preview.path, fileName: preview.name)
                }
            }
        }
    }
}

// MARK: - Shared Modifiers

/// Extracted as a ViewModifier so iOS and macOS layouts share the same
/// deep link and notification handling.
private struct SharedModifiers: ViewModifier {
    @Binding var selectedTab: AppTab
    @Binding var deepLinkPath: String?
    @Binding var agentDeepLink: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: deepLinkPath) { _, path in
                guard let path else { return }
                handleDeepLink(path)
                deepLinkPath = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .nativeNavigateRequest)) { notification in
                guard let path = notification.userInfo?["path"] as? String else { return }
                handleDeepLink(path)
            }
    }

    private func handleDeepLink(_ path: String) {
        if path == "/" || path.hasPrefix("/file") {
            selectedTab = .data
        } else if path.hasPrefix("/explore") {
            selectedTab = .explore
        } else if path.hasPrefix("/agent") {
            selectedTab = .agent
            agentDeepLink = path
        } else if path.hasPrefix("/me") {
            selectedTab = .me
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var deepLink: String? = nil
    MainTabView(deepLinkPath: $deepLink)
}
