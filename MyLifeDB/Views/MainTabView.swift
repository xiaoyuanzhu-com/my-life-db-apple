//
//  MainTabView.swift
//  MyLifeDB
//
//  Root navigation view with three tabs:
//  - Inbox: Incoming items to process
//  - Library: Organized file tree
//  - Claude: AI chat interface
//
//  Platform behavior:
//  - iOS/iPadOS: Bottom tab bar
//  - macOS: Sidebar navigation
//

import SwiftUI

enum Tab: String, CaseIterable {
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

struct MainTabView: View {
    @State private var selectedTab: Tab = .inbox

    var body: some View {
        #if os(macOS)
        // macOS: Sidebar navigation
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            selectedView
        }
        #else
        // iOS/iPadOS: Bottom tab bar
        TabView(selection: $selectedTab) {
            InboxView()
                .tabItem {
                    Label(Tab.inbox.rawValue, systemImage: Tab.inbox.icon)
                }
                .tag(Tab.inbox)

            LibraryView()
                .tabItem {
                    Label(Tab.library.rawValue, systemImage: Tab.library.icon)
                }
                .tag(Tab.library)

            ClaudeView()
                .tabItem {
                    Label(Tab.claude.rawValue, systemImage: Tab.claude.icon)
                }
                .tag(Tab.claude)

            MeView()
                .tabItem {
                    Label(Tab.me.rawValue, systemImage: Tab.me.icon)
                }
                .tag(Tab.me)
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var selectedView: some View {
        switch selectedTab {
        case .inbox:
            InboxView()
        case .library:
            LibraryView()
        case .claude:
            ClaudeView()
        case .me:
            MeView()
        }
    }
    #endif
}

#Preview {
    MainTabView()
}
