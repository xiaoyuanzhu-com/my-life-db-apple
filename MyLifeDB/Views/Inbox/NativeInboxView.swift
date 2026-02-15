//
//  NativeInboxView.swift
//  MyLifeDB
//
//  Root view for the native Inbox tab.
//  Provides NavigationStack-based navigation with
//  file detail drill-down via FileViewerView.
//  Includes searchable modifier for full-text search.
//

import SwiftUI
import Combine

// MARK: - Navigation Destination

enum InboxDestination: Hashable {
    case file(path: String, name: String)
}

// MARK: - NativeInboxView

struct NativeInboxView: View {

    @State private var navigationPath = NavigationPath()
    @State private var searchQuery = ""
    @State private var debouncedQuery = ""
    @State private var isSearchActive = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                InboxFeedContainerView()

                if isSearchActive && !debouncedQuery.isEmpty {
                    InboxSearchView(query: debouncedQuery)
                        .background(Color.platformBackground)
                }
            }
            .navigationDestination(for: InboxDestination.self) { destination in
                switch destination {
                case .file(let path, let name):
                    FileViewerView(filePath: path, fileName: name)
                }
            }
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always)
            )
            .onChange(of: searchQuery) { _, newValue in
                isSearchActive = !newValue.isEmpty
                debounceSearch(newValue)
            }
        }
    }

    // MARK: - Search Debounce

    @State private var debounceTask: Task<Void, Never>?

    private func debounceSearch(_ query: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled {
                debouncedQuery = query
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NativeInboxView()
}
