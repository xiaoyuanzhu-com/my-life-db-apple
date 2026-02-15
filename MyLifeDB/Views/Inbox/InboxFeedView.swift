//
//  InboxFeedView.swift
//  MyLifeDB
//
//  Chat-style feed for displaying inbox items.
//  Items displayed oldest at top, newest at bottom.
//  Infinite scroll: sentinel at top triggers loading older items.
//  Stick-to-bottom: auto-scrolls to newest on new items.
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

    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 16) {
                // Top sentinel for loading older items
                if hasOlderItems {
                    topSentinel
                }

                // Items in reverse order (oldest first for chat layout)
                ForEach(items.reversed()) { item in
                    itemView(for: item)
                        .id(item.id)
                }

                // Pending items at bottom (newest)
                ForEach(pendingItems) { pending in
                    PendingItemView(
                        item: pending,
                        onCancel: { onPendingCancel(pending) },
                        onRetry: { onPendingRetry(pending) }
                    )
                    .id("pending-\(pending.id)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y < 1000
        } action: { _, isNearTop in
            if isNearTop && hasOlderItems && !isLoadingMore {
                onLoadMore()
            }
        }
        .onChange(of: scrollToBottomTrigger) { _, _ in
            withAnimation(.easeOut(duration: 0.3)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    // MARK: - Top Sentinel (Infinite Scroll)

    private var topSentinel: some View {
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
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
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
