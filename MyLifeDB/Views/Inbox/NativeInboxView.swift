//
//  NativeInboxView.swift
//  MyLifeDB
//
//  Root view for the native Inbox tab.
//  Provides NavigationStack-based navigation.
//  File preview is handled by the full-screen overlay in MainTabView.
//

import SwiftUI

// MARK: - Navigation Destination

enum InboxDestination: Hashable {
    case file(path: String, name: String)
}

// MARK: - NativeInboxView

struct NativeInboxView: View {

    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            InboxFeedContainerView()
        }
    }
}

// MARK: - Preview

#Preview {
    NativeInboxView()
}
