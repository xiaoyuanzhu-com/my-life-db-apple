//
//  InboxFeedView.swift
//  MyLifeDB
//
//  Chat-style feed using .defaultScrollAnchor(.bottom).
//  Items are displayed oldest-at-top, newest-at-bottom.
//  The scroll view starts anchored at the bottom so the
//  newest items are visible first, and older items load
//  at the top as the user scrolls up.
//
//  Uses .defaultScrollAnchor(.bottom, for: .sizeChanges)
//  to stay anchored at the bottom when content height grows
//  (e.g. async image loading expanding placeholders).
//

import SwiftUI

struct InboxFeedView: View {

    @Environment(\.openFilePreview) private var openFilePreview
    @Environment(\.previewNamespace) private var previewNamespace

    let items: [InboxItem]
    let pinnedItems: [PinnedItem]
    let pendingItems: [PendingInboxItem]
    let isLoadingMore: Bool
    let hasOlderItems: Bool
    let scrollToBottomTrigger: Int
    let onLoadMore: () -> Void
    let onItemDelete: (InboxItem) -> Void
    let onItemPin: (InboxItem) -> Void
    let onPendingCancel: (PendingInboxItem) -> Void
    let onPendingRetry: (PendingInboxItem) -> Void
    let onPinnedTap: (PinnedItem) -> Void
    let onPinnedUnpin: (PinnedItem) -> Void
    let onLoadMoreForPreview: () async -> [PreviewItem]
    let onRefresh: () async -> Void

    @State private var scrollPosition = ScrollPosition(idType: String.self)
    /// Gates pagination until the initial scroll settles at the bottom.
    /// Without this, the sentinel onAppear and onScrollGeometryChange fire
    /// before .defaultScrollAnchor(.bottom) takes effect, eagerly loading
    /// older pages and breaking the initial scroll position.
    @State private var paginationEnabled = false
    @State private var isRefreshingFromBottom = false

    private let newestAnchorID = "feed-newest"

    private var maxCardWidth: CGFloat {
        #if os(iOS) || os(visionOS)
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return (scene?.screen.bounds.width ?? 393) * 0.8
        #elseif os(macOS)
        return (NSScreen.main?.frame.width ?? 800) * 0.8
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 16) {
                // Sentinel (top = oldest area)
                if hasOlderItems {
                    olderItemsSentinel
                }

                // Items: oldest first (reverse the newest-first array)
                ForEach(items.reversed()) { item in
                    itemView(for: item)
                        .frame(maxWidth: maxCardWidth)
                        .id(item.id)
                }

                // Pending items (bottom = newest area)
                ForEach(pendingItems) { pending in
                    PendingItemView(
                        item: pending,
                        onCancel: { onPendingCancel(pending) },
                        onRetry: { onPendingRetry(pending) }
                    )
                    .id("pending-\(pending.id)")
                }

                // Pinned bar + newest anchor (bottom, closest to input)
                VStack(spacing: 0) {
                    if !pinnedItems.isEmpty {
                        InboxPinnedBar(
                            items: pinnedItems,
                            onTap: onPinnedTap,
                            onUnpin: onPinnedUnpin
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, -8)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(newestAnchorID)
                        .onAppear {
                            if !paginationEnabled {
                                paginationEnabled = true
                                // Correct any scroll overshoot from LazyVStack height estimation
                                scrollPosition.scrollTo(id: newestAnchorID, anchor: .bottom)
                            }
                        }
                }

                // Bottom refresh indicator (pull-up-to-refresh)
                if isRefreshingFromBottom {
                    ProgressView()
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let maxOffset = geometry.contentSize.height - geometry.containerSize.height
            return maxOffset > 0 && geometry.contentOffset.y < 1000
        } action: { _, isNearOlderEnd in
            if paginationEnabled && isNearOlderEnd && hasOlderItems && !isLoadingMore {
                onLoadMore()
            }
        }
        // Pull-up-to-refresh: detect overscroll past the bottom edge
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
            let overscroll = visibleBottom - geometry.contentSize.height
            return max(0, overscroll)
        } action: { _, overscroll in
            let threshold: CGFloat = 60
            if overscroll > threshold && !isRefreshingFromBottom {
                isRefreshingFromBottom = true
                Task {
                    await onRefresh()
                    isRefreshingFromBottom = false
                }
            }
        }
        .onChange(of: scrollToBottomTrigger) { _, _ in
            withAnimation(.easeOut(duration: 0.3)) {
                scrollPosition.scrollTo(id: newestAnchorID, anchor: .bottom)
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
            if paginationEnabled {
                onLoadMore()
            }
        }
    }

    // MARK: - Item View

    @ViewBuilder
    private func itemView(for item: InboxItem) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            InboxTimestampView(epochMs: item.createdAt)

            Button {
                let pagerContext = mediaPagerContext(for: item)
                openFilePreview?(item.path, item.name, item.asFileRecord, pagerContext)
            } label: {
                InboxItemCard(item: item)
            }
            .buttonStyle(.plain)
            .previewSource(
                path: item.path,
                namespace: previewNamespace
            )
            .contextMenu {
                contextMenuContent(for: item)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Media Pager Context

    /// Builds a pager context for media (image/video) items only.
    /// Returns nil for non-media items so they open as standalone previews.
    private func mediaPagerContext(for item: InboxItem) -> FilePreviewPagerContext? {
        guard item.isImage || item.isVideo else { return nil }

        let mediaItems = items.filter { $0.isImage || $0.isVideo }
        let previewItems = mediaItems.map {
            PreviewItem(path: $0.path, name: $0.name, file: $0.asFileRecord)
        }

        guard let startIndex = mediaItems.firstIndex(where: { $0.path == item.path }) else {
            return nil
        }

        return FilePreviewPagerContext(
            items: previewItems,
            startIndex: startIndex,
            hasMoreOlder: hasOlderItems,
            loadMore: onLoadMoreForPreview
        )
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
