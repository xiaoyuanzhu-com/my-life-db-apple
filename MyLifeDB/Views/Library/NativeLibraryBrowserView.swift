//
//  NativeLibraryBrowserView.swift
//  MyLifeDB
//
//  Root view for the native Library tab.
//  Provides NavigationStack-based folder drill-down,
//  similar to the iOS Files app experience.
//  File preview is handled by the full-screen overlay in MainTabView.
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

    @State private var navigationPath = NavigationPath()
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .grid

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Root folder (path = "")
            LibraryFolderView(
                folderPath: "",
                folderName: "Library",
                viewMode: $viewMode,
                navigationPath: $navigationPath
            )
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .folder(let path, let name):
                    LibraryFolderView(
                        folderPath: path,
                        folderName: name,
                        viewMode: $viewMode,
                        navigationPath: $navigationPath
                    )
                case .file:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NativeLibraryBrowserView()
}
