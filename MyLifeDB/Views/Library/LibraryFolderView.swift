//
//  LibraryFolderView.swift
//  MyLifeDB
//
//  Displays the contents of a single library directory.
//  Handles loading, error, empty, and content states.
//  Supports grid and list view modes.
//

import SwiftUI

struct LibraryFolderView: View {

    let folderPath: String
    let folderName: String
    @Binding var viewMode: LibraryViewMode

    @State private var children: [FileTreeNode] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading && children.isEmpty {
                loadingView
            } else if let error = error, children.isEmpty {
                errorView(error)
            } else if children.isEmpty && !isLoading {
                emptyView
            } else {
                contentView
            }
        }
        .navigationTitle(folderName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        viewMode = viewMode == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                }
                .accessibilityLabel(viewMode == .grid ? "Switch to list view" : "Switch to grid view")
            }
        }
        .task {
            if children.isEmpty {
                await loadChildren()
            }
        }
        .refreshable {
            await loadChildren()
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            LibraryGridView(children: children, folderPath: folderPath)
        case .list:
            LibraryListView(children: children, folderPath: folderPath)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Failed to Load")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task { await loadChildren() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Empty Folder", systemImage: "folder")
        } description: {
            Text("This folder has no files or subfolders.")
        }
    }

    // MARK: - Data Fetching

    private func loadChildren() async {
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.library.getTree(path: folderPath, depth: 1)
            children = response.children
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
