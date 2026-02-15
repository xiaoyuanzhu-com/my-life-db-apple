//
//  InboxFeedContainerView.swift
//  MyLifeDB
//
//  Main data-owning container for the inbox feed.
//  Manages loading, pagination, and all inbox state.
//

import SwiftUI

struct InboxFeedContainerView: View {

    // MARK: - State

    @State private var items: [InboxItem] = []
    @State private var pinnedItems: [PinnedItem] = []
    @State private var isLoading = false
    @State private var error: APIError?
    @State private var cursors: InboxCursors?
    @State private var hasMore = InboxHasMore(older: false, newer: false)

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                loadingView
            } else if let error = error, items.isEmpty {
                errorView(error)
            } else if items.isEmpty && !isLoading {
                emptyView
            } else {
                Text("Feed placeholder — \(items.count) items")
            }
        }
        .navigationTitle("Inbox")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadInitialData()
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading inbox...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: APIError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Failed to Load")
                .font(.headline)

            Text(error.userMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task { await loadInitialData() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Items", systemImage: "tray")
        } description: {
            Text("Your inbox is empty.\nAdd something to get started!")
        }
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadItems() }
            group.addTask { await loadPinnedItems() }
        }
    }

    private func loadItems() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.inbox.list()
            items = response.items
            cursors = response.cursors
            hasMore = response.hasMore
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }

        isLoading = false
    }

    private func loadPinnedItems() async {
        do {
            let response = try await APIClient.shared.inbox.listPinned()
            pinnedItems = response.items
        } catch {
            print("[Inbox] Failed to load pinned items: \(error)")
        }
    }

    private func refresh() async {
        do {
            async let itemsTask = APIClient.shared.inbox.list()
            async let pinnedTask = APIClient.shared.inbox.listPinned()

            let (itemsResponse, pinnedResponse) = try await (itemsTask, pinnedTask)

            items = itemsResponse.items
            cursors = itemsResponse.cursors
            hasMore = itemsResponse.hasMore
            pinnedItems = pinnedResponse.items
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }
}
