//
//  NativeLibraryBrowserView.swift
//  MyLifeDB
//
//  Root view for the native Library tab.
//  Provides NavigationStack-based folder drill-down,
//  similar to the iOS Files app experience.
//

import SwiftUI

// MARK: - Navigation Destination

/// Destinations reachable from the library browser.
enum LibraryDestination: Hashable {
    case folder(path: String, name: String)
    case file(path: String, name: String)
}

// MARK: - View Mode

/// Grid vs list toggle for the library browser.
enum LibraryViewMode: String, CaseIterable {
    case grid
    case list

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }
}

// MARK: - NativeLibraryBrowserView

struct NativeLibraryBrowserView: View {

    @Namespace private var previewNamespace
    @State private var navigationPath = NavigationPath()
    @State private var filePreview: FilePreviewDestination?
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .grid

    var body: some View {
        ZStack {
            NavigationStack(path: $navigationPath) {
                // Root folder (path = "")
                LibraryFolderView(
                    folderPath: "",
                    folderName: "Library",
                    viewMode: $viewMode
                )
                .navigationDestination(for: LibraryDestination.self) { destination in
                    switch destination {
                    case .folder(let path, let name):
                        LibraryFolderView(
                            folderPath: path,
                            folderName: name,
                            viewMode: $viewMode
                        )
                    case .file:
                        EmptyView()
                    }
                }
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
    NativeLibraryBrowserView()
}
