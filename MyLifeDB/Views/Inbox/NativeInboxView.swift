//
//  NativeInboxView.swift
//  MyLifeDB
//
//  Root view for the native Inbox tab.
//  Provides NavigationStack-based navigation with
//  file detail drill-down via FileViewerView.
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
                .navigationDestination(for: InboxDestination.self) { destination in
                    switch destination {
                    case .file(let path, let name):
                        FileViewerView(filePath: path, fileName: name)
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    NativeInboxView()
}
