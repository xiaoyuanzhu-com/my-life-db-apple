//
//  InboxFeedView.swift
//  MyLifeDB
//
//  Chat-style feed using a flipped ScrollView pattern.
//  The ScrollView is vertically inverted so that:
//    - Internal top (offset 0) = visual bottom = newest items
//    - Internal bottom = visual top = oldest items
//  Loading older items appends to the internal bottom,
//  which never shifts the scroll position. No anchoring needed.
//

import SwiftUI

struct InboxFeedView: View {

    let items: [InboxItem]
    let pendingItems: [PendingInboxItem]
    let isLoadingMore: Bool
    let hasOlderItems: Bool
    let scrollToBottomTrigger: Int
    let onLoadMore: () -> Void
    let onItemDelete: (InboxItem) -> Void
    let onItemPin: (InboxItem) -> Void
    let onPendingCancel: (PendingInboxItem) -> Void
    let onPendingRetry: (PendingInboxItem) -> Void

    private let newestAnchorID = "feed-newest"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 16) {
                    // Newest anchor (internal top = visual bottom)
                    Color.clear
                        .frame(height: 1)
                        .id(newestAnchorID)

                    // Pending items (visual bottom, newest area)
                    ForEach(pendingItems.reversed()) { pending in
                        PendingItemView(
                            item: pending,
                            onCancel: { onPendingCancel(pending) },
                            onRetry: { onPendingRetry(pending) }
                        )
                        .id("pending-\(pending.id)")
                        .flippedForChat()
                    }

                    // Items: newest first (no .reversed() needed)
                    ForEach(items) { item in
                        itemView(for: item)
                            .id(item.id)
                            .flippedForChat()
                    }

                    // Sentinel (internal bottom = visual top, oldest area)
                    if hasOlderItems {
                        olderItemsSentinel
                            .flippedForChat()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let maxOffset = geometry.contentSize.height - geometry.containerSize.height
                return maxOffset > 0 && (maxOffset - geometry.contentOffset.y) < 1000
            } action: { _, isNearOlderEnd in
                if isNearOlderEnd && hasOlderItems && !isLoadingMore {
                    onLoadMore()
                }
            }
            .flippedForChat()
            .onChange(of: scrollToBottomTrigger) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(newestAnchorID, anchor: .top)
                }
            }
        }
    }

    // MARK: - Older Items Sentinel

    private var olderItemsSentinel: some View {
        VStack(spacing: 0) {
            if isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 1)
        .onAppear {
            onLoadMore()
        }
    }

    // MARK: - Item View

    @ViewBuilder
    private func itemView(for item: InboxItem) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            InboxTimestampView(dateString: item.createdAt)

            NavigationLink(value: InboxDestination.file(path: item.path, name: item.name)) {
                InboxItemCard(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu {
                contextMenuContent(for: item)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuContent(for item: InboxItem) -> some View {
        Button {
            onItemPin(item)
        } label: {
            Label(
                item.isPinned ? "Unpin" : "Pin",
                systemImage: item.isPinned ? "pin.slash" : "pin"
            )
        }

        Divider()

        Button(role: .destructive) {
            onItemDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Flipped Layout Helper

private extension View {
    /// Flips a view vertically for inverted scroll layout (chat-style).
    func flippedForChat() -> some View {
        scaleEffect(x: 1, y: -1)
    }
}
