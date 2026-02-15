//
//  NativeInboxView.swift
//  MyLifeDB
//
//  Root view for the native Inbox tab.
//  Provides NavigationStack-based navigation with
//  file detail drill-down via FileViewerView.
//  Search is integrated into the input bar (no separate search bar).
//

import SwiftUI

// MARK: - Navigation Destination

enum InboxDestination: Hashable {
    case file(path: String, name: String)
}

// MARK: - NativeInboxView

struct NativeInboxView: View {

    @State private var navigationPath = NavigationPath()
    @State private var filePreview: FilePreviewDestination?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            InboxFeedContainerView()
        }
        .environment(\.openFilePreview) { path, name in
            filePreview = FilePreviewDestination(path: path, name: name)
        }
        .fullScreenCover(item: $filePreview) { preview in
            FileViewerView(filePath: preview.path, fileName: preview.name)
        }
    }
}

// MARK: - Preview

#Preview {
    NativeInboxView()
}
