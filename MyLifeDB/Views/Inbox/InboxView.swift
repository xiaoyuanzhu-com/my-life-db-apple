//
//  InboxView.swift
//  MyLifeDB
//
//  Displays inbox items from the backend API.
//  Items are files that need to be processed/organized.
//
//  API: GET /api/inbox
//

import SwiftUI

struct InboxView: View {

    // MARK: - State

    @State private var items: [InboxItem] = []
    @State private var isLoading = false
    @State private var error: APIError?
    @State private var cursors: InboxCursors?
    @State private var hasMore = InboxHasMore(older: false, newer: false)

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading...")
                } else if let error = error, items.isEmpty {
                    errorView(error)
                } else if items.isEmpty {
                    emptyView
                } else {
                    itemsList
                }
            }
            .navigationTitle("Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
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
        }
        .task {
            await loadItems()
        }
    }

    // MARK: - Views

    private var itemsList: some View {
        List {
            ForEach(items) { item in
                InboxItemRow(item: item)
            }
            .onDelete(perform: deleteItems)

            // Load more button
            if hasMore.older {
                Button {
                    Task { await loadMore() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Load More")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .refreshable {
            await refresh()
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Items",
            systemImage: "tray",
            description: Text("Your inbox is empty")
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
        }
    }

    // MARK: - Data Loading

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

    private func refresh() async {
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

    private func loadMore() async {
        guard let lastCursor = cursors?.last, hasMore.older else { return }

        isLoading = true

        do {
            let response = try await APIClient.shared.inbox.fetchOlder(cursor: lastCursor)
            items.append(contentsOf: response.items)
            cursors = response.cursors
            hasMore = response.hasMore
        } catch {
            // Silently fail for load more
        }

        isLoading = false
    }

    private func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { items[$0] }

        // Optimistically remove from UI
        items.remove(atOffsets: offsets)

        // Delete from server
        Task {
            for item in itemsToDelete {
                let id = InboxAPI.idFromPath(item.path)
                do {
                    try await APIClient.shared.inbox.delete(id: id)
                } catch {
                    // Reload on failure
                    await loadItems()
                    break
                }
            }
        }
    }
}

// MARK: - Inbox Item Row

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
