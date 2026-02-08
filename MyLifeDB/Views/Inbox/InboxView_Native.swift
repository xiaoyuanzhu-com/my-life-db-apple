#if LEGACY_NATIVE_VIEWS
//
//  InboxView.swift
//  MyLifeDB
//
//  Main inbox view with chat-style feed, input bar, and pinned items.
//  Items are displayed newest at bottom, scroll up for history.
//
//  API: GET /api/inbox
//

import SwiftUI

struct InboxView: View {

    // MARK: - State

    /// Inbox items (API order: newest first)
    @State private var items: [InboxItem] = []

    /// Pinned items for quick navigation
    @State private var pinnedItems: [PinnedItem] = []

    /// Loading states
    @State private var isLoading = false
    @State private var isLoadingMore = false

    /// Error state
    @State private var error: APIError?

    /// Pagination
    @State private var cursors: InboxCursors?
    @State private var hasMore = InboxHasMore(older: false, newer: false)

    /// Input text
    @State private var inputText = ""

    /// Selected item for detail modal
    @State private var selectedItem: InboxItem?

    /// Sending state
    @State private var isSending = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main content
                mainContent

                Divider()

                // Pinned items bar
                PinnedItemsBar(
                    items: pinnedItems,
                    onTap: { pinnedItem in
                        navigateToPinnedItem(pinnedItem)
                    },
                    onUnpin: { pinnedItem in
                        Task { await unpinItem(pinnedItem) }
                    }
                )

                // Input bar
                InboxInputBar(text: $inputText) { text, files in
                    Task { await createItem(text: text, files: files) }
                }
            }
            .navigationTitle("Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailModal(item: item, allItems: items)
            }
        }
        .task {
            await loadInitialData()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isLoading && items.isEmpty {
            loadingView
        } else if let error = error, items.isEmpty {
            errorView(error)
        } else if items.isEmpty {
            emptyView
        } else {
            feedView
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading inbox...")
            Spacer()
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Items",
            systemImage: "tray",
            description: Text("Your inbox is empty.\nAdd something to get started!")
        )
    }

    private func errorView(_ error: APIError) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.userMessage)
        } actions: {
            Button("Retry") {
                Task { await loadItems() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var feedView: some View {
        InboxFeedView(
            items: items,
            isLoadingMore: isLoadingMore,
            hasOlderItems: hasMore.older,
            onLoadMore: {
                Task { await loadMore() }
            },
            onItemTap: { item in
                selectedItem = item
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
            // Silently fail for pinned items
            print("Failed to load pinned items: \(error)")
        }
    }

    private func refresh() async {
        isLoading = true
        error = nil

        do {
            async let itemsTask = APIClient.shared.inbox.list()
            async let pinnedTask = APIClient.shared.inbox.listPinned()

            let (itemsResponse, pinnedResponse) = try await (itemsTask, pinnedTask)

            items = itemsResponse.items
            cursors = itemsResponse.cursors
            hasMore = itemsResponse.hasMore
            pinnedItems = pinnedResponse.items
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }

        isLoading = false
    }

    private func loadMore() async {
        guard let lastCursor = cursors?.last, hasMore.older, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let response = try await APIClient.shared.inbox.fetchOlder(cursor: lastCursor)
            items.append(contentsOf: response.items)
            cursors = response.cursors
            hasMore = response.hasMore
        } catch {
            // Silently fail for load more
            print("Failed to load more: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - Actions

    private func createItem(text: String, files: [FileAttachment]) async {
        guard !isSending else { return }
        isSending = true

        do {
            if !files.isEmpty {
                // Upload files
                let fileData = files.map { (filename: $0.filename, data: $0.data, mimeType: $0.mimeType) }
                _ = try await APIClient.shared.inbox.uploadFiles(fileData, text: text.isEmpty ? nil : text)
            } else if !text.isEmpty {
                // Create text item
                _ = try await APIClient.shared.inbox.createText(text)
            }

            // Refresh to show new item
            await refresh()
        } catch {
            print("Failed to create item: \(error)")
        }

        isSending = false
    }

    private func deleteItem(_ item: InboxItem) async {
        // Optimistic update
        withAnimation(.easeOut(duration: 0.3)) {
            items.removeAll { $0.id == item.id }
        }

        // Also remove from pinned if applicable
        pinnedItems.removeAll { $0.path == item.path }

        // Delete from server
        let id = InboxAPI.idFromPath(item.path)
        do {
            try await APIClient.shared.inbox.delete(id: id)
        } catch {
            // Reload on failure
            print("Failed to delete item: \(error)")
            await loadItems()
        }
    }

    private func togglePin(_ item: InboxItem) async {
        do {
            _ = try await APIClient.shared.library.pin(path: item.path)
            // Refresh both lists
            await refresh()
        } catch {
            print("Failed to toggle pin: \(error)")
        }
    }

    private func unpinItem(_ pinnedItem: PinnedItem) async {
        // Optimistic update
        pinnedItems.removeAll { $0.path == pinnedItem.path }

        // Update on server
        do {
            try await APIClient.shared.library.unpin(path: pinnedItem.path)
            // Also update the item in the feed if visible
            if let index = items.firstIndex(where: { $0.path == pinnedItem.path }) {
                // Can't modify isPinned directly, so just refresh
                await loadItems()
            }
        } catch {
            print("Failed to unpin: \(error)")
            await loadPinnedItems()
        }
    }

    private func navigateToPinnedItem(_ pinnedItem: PinnedItem) {
        // Find the item in the feed
        if let item = items.first(where: { $0.path == pinnedItem.path }) {
            selectedItem = item
        } else {
            // Item not loaded, could implement scroll-to functionality
            // For now, just open the detail
            // TODO: Implement scroll to cursor
        }
    }
}

// MARK: - Legacy Inbox Item Row (kept for backwards compatibility)

struct InboxItemRow: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let size = item.formattedSize {
                        Text(size)
                    }

                    Text(item.processingStatus.displayName)
                        .foregroundStyle(statusColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Pin indicator
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        if item.isFolder {
            return "folder.fill"
        } else if item.isImage {
            return "photo"
        } else if item.isVideo {
            return "video"
        } else {
            return "doc"
        }
    }

    private var iconColor: Color {
        if item.isFolder {
            return .blue
        } else if item.isImage {
            return .green
        } else if item.isVideo {
            return .purple
        } else {
            return .gray
        }
    }

    private var statusColor: Color {
        switch item.processingStatus {
        case .pending: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    InboxView()
}

#endif // LEGACY_NATIVE_VIEWS
