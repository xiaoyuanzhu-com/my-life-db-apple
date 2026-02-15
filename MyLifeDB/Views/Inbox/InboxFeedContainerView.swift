//
//  InboxFeedContainerView.swift
//  MyLifeDB
//
//  Main data-owning container for the inbox feed.
//  Manages loading, pagination, upload, search, and all inbox state.
//

import SwiftUI

struct InboxFeedContainerView: View {

    // MARK: - State

    @State private var items: [InboxItem] = []
    @State private var pinnedItems: [PinnedItem] = []
    @State private var pendingItems: [PendingInboxItem] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var error: APIError?
    @State private var cursors: InboxCursors?
    @State private var hasMore = InboxHasMore(older: false, newer: false)
    @State private var sseManager = InboxSSEManager()

    @State private var scrollToBottomTrigger = 0

    // Search state
    @State private var searchResults: [SearchResultItem] = []
    @State private var searchStatus = InboxSearchStatus()
    @State private var isShowingSearch = false
    @State private var searchTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main content area — feed or search results
            Group {
                if isLoading && items.isEmpty {
                    loadingView
                } else if let error = error, items.isEmpty {
                    errorView(error)
                } else if isShowingSearch {
                    searchResultsView
                } else if items.isEmpty && !isLoading && pendingItems.isEmpty {
                    emptyView
                } else {
                    feedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom section: pins + input
            VStack(spacing: 0) {
                // Pinned items bar
                InboxPinnedBar(
                    items: pinnedItems,
                    onTap: { pinnedItem in
                        Task { await navigateToPinnedItem(pinnedItem) }
                    },
                    onUnpin: { pinnedItem in
                        Task { await unpinItem(pinnedItem) }
                    }
                )

                // Input bar at bottom
                InboxInputBar(
                    onSend: { text, files in
                        createItem(text: text, files: files)
                    },
                    onTextChange: { text in
                        handleTextChange(text)
                    },
                    searchStatus: searchStatus
                )
            }
            .background(Color(.systemBackground))
        }
        .navigationTitle("Inbox")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            await loadInitialData()
            setupSSE()
        }
        .onDisappear {
            sseManager.stop()
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
            pendingItems: pendingItems,
            isLoadingMore: isLoadingMore,
            hasOlderItems: hasMore.older,
            scrollToBottomTrigger: scrollToBottomTrigger,
            onLoadMore: {
                Task { await loadOlderItems() }
            },
            onItemDelete: { item in
                Task { await deleteItem(item) }
            },
            onItemPin: { item in
                Task { await togglePin(item) }
            },
            onPendingCancel: { pending in
                pendingItems.removeAll { $0.id == pending.id }
            },
            onPendingRetry: { pending in
                Task { await retryPendingItem(pending) }
            }
        )
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        InboxSearchView(results: searchResults, isSearching: searchStatus.isSearching)
    }

    // MARK: - Search

    private func handleTextChange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cancel previous search
        searchTask?.cancel()

        if trimmed.count < 2 {
            isShowingSearch = false
            searchResults = []
            searchStatus = InboxSearchStatus()
            return
        }

        // Debounce search
        let delay: UInt64 = trimmed.count <= 2 ? 500_000_000 : 100_000_000

        searchTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                searchStatus.isSearching = true
            }

            do {
                let response = try await APIClient.shared.search.search(
                    query: trimmed,
                    limit: 20,
                    offset: 0
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    searchResults = response.results
                    searchStatus = InboxSearchStatus(
                        isSearching: false,
                        resultCount: response.results.count,
                        hasError: false
                    )
                    isShowingSearch = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchStatus = InboxSearchStatus(
                        isSearching: false,
                        resultCount: 0,
                        hasError: true
                    )
                    isShowingSearch = true
                }
            }
        }
    }

    // MARK: - SSE

    private func setupSSE() {
        sseManager.onInboxChanged = {
            Task { await refreshItems() }
        }
        sseManager.onPinChanged = {
            Task { await loadPinnedItems() }
        }
        sseManager.start()
    }

    private func refreshItems() async {
        do {
            let response = try await APIClient.shared.inbox.list()
            withAnimation(.easeOut(duration: 0.35)) {
                items = response.items
            }
            cursors = response.cursors
            hasMore = response.hasMore
            scrollToBottomTrigger += 1
        } catch {
            print("[Inbox] SSE refresh failed: \(error)")
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
            scrollToBottomTrigger += 1
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
            scrollToBottomTrigger += 1
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

    private func unpinItem(_ pinnedItem: PinnedItem) async {
        pinnedItems.removeAll { $0.path == pinnedItem.path }

        do {
            try await APIClient.shared.library.unpin(path: pinnedItem.path)
            await loadItems()
        } catch {
            print("[Inbox] Failed to unpin: \(error)")
            await loadPinnedItems()
        }
    }

    private func navigateToPinnedItem(_ pinnedItem: PinnedItem) async {
        do {
            let response = try await APIClient.shared.inbox.list(around: pinnedItem.cursor)
            items = response.items
            cursors = response.cursors
            hasMore = response.hasMore
        } catch {
            print("[Inbox] Failed to navigate to pinned item: \(error)")
        }
    }

    // MARK: - Upload

    private func createItem(text: String, files: [InboxFileAttachment]) {
        let pendingId = UUID().uuidString
        let pending = PendingInboxItem(
            id: pendingId,
            text: text,
            files: files,
            status: .uploading
        )
        pendingItems.append(pending)
        scrollToBottomTrigger += 1

        Task {
            await uploadPendingItem(pending)
        }
    }

    private func uploadPendingItem(_ item: PendingInboxItem) async {
        do {
            if !item.files.isEmpty {
                let fileData = item.files.map {
                    (filename: $0.filename, data: $0.data, mimeType: $0.mimeType)
                }
                _ = try await APIClient.shared.inbox.uploadFiles(
                    fileData,
                    text: item.text.isEmpty ? nil : item.text
                )
            } else if !item.text.isEmpty {
                _ = try await APIClient.shared.inbox.createText(item.text)
            }

            pendingItems.removeAll { $0.id == item.id }
            await refresh()
        } catch {
            if let index = pendingItems.firstIndex(where: { $0.id == item.id }) {
                pendingItems[index].status = .failed
                pendingItems[index].error = error.localizedDescription
                pendingItems[index].retryCount += 1

                if pendingItems[index].retryCount < 3 {
                    let delay = Double(pendingItems[index].retryCount * pendingItems[index].retryCount) * 5
                    pendingItems[index].status = .queued
                    pendingItems[index].retryAt = Date().addingTimeInterval(delay)

                    try? await Task.sleep(for: .seconds(delay))
                    if let current = pendingItems.first(where: { $0.id == item.id }),
                       current.status == .queued {
                        await uploadPendingItem(current)
                    }
                }
            }
        }
    }

    private func retryPendingItem(_ item: PendingInboxItem) async {
        if let index = pendingItems.firstIndex(where: { $0.id == item.id }) {
            pendingItems[index].status = .uploading
            pendingItems[index].error = nil
        }
        await uploadPendingItem(item)
    }
}
