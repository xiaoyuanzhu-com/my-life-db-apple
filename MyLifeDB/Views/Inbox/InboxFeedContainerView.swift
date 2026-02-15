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
    @State private var isLoadingMore = false
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
                feedView
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

    // MARK: - Feed View

    private var feedView: some View {
        InboxFeedView(
            items: items,
            isLoadingMore: isLoadingMore,
            hasOlderItems: hasMore.older,
            onLoadMore: {
                Task { await loadOlderItems() }
            },
            onItemDelete: { item in
                Task { await deleteItem(item) }
            },
            onItemPin: { item in
                Task { await togglePin(item) }
            }
        )
        .refreshable {
            await refresh()
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

    private func loadOlderItems() async {
        guard let lastCursor = cursors?.last, hasMore.older, !isLoadingMore else { return }
        isLoadingMore = true

        do {
            let response = try await APIClient.shared.inbox.fetchOlder(cursor: lastCursor)
            items.append(contentsOf: response.items)
            cursors = response.cursors
            hasMore = response.hasMore
        } catch {
            print("[Inbox] Failed to load more: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Actions

    private func deleteItem(_ item: InboxItem) async {
        withAnimation(.easeOut(duration: 0.3)) {
            items.removeAll { $0.id == item.id }
        }
        pinnedItems.removeAll { $0.path == item.path }

        let id = InboxAPI.idFromPath(item.path)
        do {
            try await APIClient.shared.inbox.delete(id: id)
        } catch {
            print("[Inbox] Failed to delete item: \(error)")
            await loadItems()
        }
    }

    private func togglePin(_ item: InboxItem) async {
        do {
            if item.isPinned {
                try await APIClient.shared.library.unpin(path: item.path)
            } else {
                _ = try await APIClient.shared.library.pin(path: item.path)
            }
            await refresh()
        } catch {
            print("[Inbox] Failed to toggle pin: \(error)")
        }
    }
}
