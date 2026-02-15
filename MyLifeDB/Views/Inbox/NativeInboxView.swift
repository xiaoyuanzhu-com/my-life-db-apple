//
//  NativeInboxView.swift
//  MyLifeDB
//
//  Root view for the native Inbox tab.
//  Provides NavigationStack-based navigation with
//  file preview presented as a zoom-animated overlay.
//

import SwiftUI

// MARK: - Navigation Destination

enum InboxDestination: Hashable {
    case file(path: String, name: String)
}

// MARK: - NativeInboxView

struct NativeInboxView: View {

    @Namespace private var previewNamespace
    @State private var navigationPath = NavigationPath()
    @State private var filePreview: FilePreviewDestination?

    var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                InboxFeedContainerView()
            }
            .environment(\.openFilePreview) { path, name in
                withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                    filePreview = FilePreviewDestination(path: path, name: name)
                }
            }
            .environment(\.previewNamespace, previewNamespace)
            .environment(\.activePreviewPath, filePreview?.path)

            if let preview = filePreview {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)

                FileViewerView(
                    filePath: preview.path,
                    fileName: preview.name,
                    onDismiss: {
                        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                            filePreview = nil
                        }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NativeInboxView()
}
