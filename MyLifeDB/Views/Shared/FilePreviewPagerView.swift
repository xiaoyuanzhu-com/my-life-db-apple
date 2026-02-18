//
//  FilePreviewPagerView.swift
//  MyLifeDB
//
//  Horizontal pager for swiping between media files (images and videos)
//  in the inbox file preview. Uses a simple ScrollView with paging so
//  each item sits side by side at full width. Non-media files are
//  excluded from the pager.
//
//  Items are displayed in chronological order (oldest on the left,
//  newest on the right) so swiping left goes toward newer items
//  and swiping right toward older.
//
//  The context.items array arrives newest-first from the feed, so it
//  is reversed here to get oldest-first (left-to-right chronological).
//

import SwiftUI

struct FilePreviewPagerView: View {

    let onDismiss: () -> Void

    // Items in chronological order (oldest first / leftmost).
    // Reversed from the feed's newest-first order.
    @State private var items: [PreviewItem]
    @State private var currentID: String?
    @State private var isLoadingMore = false
    @State private var hasMoreOlder: Bool

    private let loadMore: () async -> [PreviewItem]

    init(context: FilePreviewPagerContext, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.loadMore = context.loadMore
        // Reverse so oldest is first (leftmost in the pager).
        self._items = State(initialValue: context.items.reversed())
        self._hasMoreOlder = State(initialValue: context.hasMoreOlder)
        // Use the item's stable ID (path) for selection, not an Int index.
        let startID = context.items.indices.contains(context.startIndex)
            ? context.items[context.startIndex].id
            : (context.items.first?.id ?? "")
        self._currentID = State(initialValue: startID)
    }

    var body: some View {
        #if os(macOS)
        // macOS: fall back to single file viewer
        if let item = items.first(where: { $0.id == currentID }) {
            FileViewerView(filePath: item.path, fileName: item.name, onDismiss: onDismiss)
        }
        #else
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        Group {
                            if let file = item.file {
                                FileViewerView(file: file, onDismiss: onDismiss)
                            } else {
                                FileViewerView(filePath: item.path, fileName: item.name, onDismiss: onDismiss)
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(item.id)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .onAppear {
                if let id = currentID {
                    proxy.scrollTo(id, anchor: .center)
                    prefetchAdjacentItems(around: id)
                }
            }
            .onChange(of: currentID) { _, newID in
                guard let newID else { return }
                // Load more older items when approaching the left end (oldest side).
                if let idx = items.firstIndex(where: { $0.id == newID }),
                   idx <= 2 && hasMoreOlder && !isLoadingMore {
                    Task { await loadMoreItems() }
                }
                // Prefetch adjacent images for smoother swiping.
                prefetchAdjacentItems(around: newID)
            }
        }
        #endif
    }

    /// Warm the FileCache for the previous and next image so swiping feels instant.
    private func prefetchAdjacentItems(around id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        for delta in [-1, 1] {
            let adjacent = idx + delta
            guard adjacent >= 0 && adjacent < items.count else { continue }
            let item = items[adjacent]
            guard item.isLikelyImage else { continue }
            let url = APIClient.shared.rawFileURL(path: item.path)
            Task { _ = try? await FileCache.shared.data(for: url) }
        }
    }

    private func loadMoreItems() async {
        isLoadingMore = true
        let newItems = await loadMore()
        if !newItems.isEmpty {
            // Prepend to the start (left / older side).
            // New items arrive newest-first from the API, reverse to oldest-first.
            items.insert(contentsOf: newItems.reversed(), at: 0)
        } else {
            hasMoreOlder = false
        }
        isLoadingMore = false
    }
}
