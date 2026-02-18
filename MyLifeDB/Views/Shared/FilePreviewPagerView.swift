//
//  FilePreviewPagerView.swift
//  MyLifeDB
//
//  Horizontal pager for swiping between media files (images and videos)
//  in the inbox file preview. Uses a simple ScrollView with paging so
//  each item sits side by side at full width. Non-media files are
//  excluded from the pager.
//
//  Items are displayed in reverse-chronological order (newest on the left)
//  so swiping left goes toward older items and swiping right toward newer.
//
//  The context.items array arrives newest-first from the feed, which is
//  already the correct left-to-right order for the pager.
//

import SwiftUI

struct FilePreviewPagerView: View {

    let onDismiss: () -> Void

    // Items in reverse-chronological order (newest first / leftmost).
    // The array arrives newest-first from the feed — no reversal needed.
    @State private var items: [PreviewItem]
    @State private var currentID: String?
    @State private var isLoadingMore = false
    @State private var hasMoreOlder: Bool

    private let loadMore: () async -> [PreviewItem]

    init(context: FilePreviewPagerContext, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.loadMore = context.loadMore
        // Items are already newest-first from the feed — use as-is.
        self._items = State(initialValue: context.items)
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
        .onChange(of: currentID) { _, newID in
            guard let newID else { return }
            // Load more older items when approaching the right end (oldest side).
            if let idx = items.firstIndex(where: { $0.id == newID }),
               idx >= items.count - 3 && hasMoreOlder && !isLoadingMore {
                Task { await loadMoreItems() }
            }
        }
        #endif
    }

    private func loadMoreItems() async {
        isLoadingMore = true
        let newItems = await loadMore()
        if !newItems.isEmpty {
            // Append to the end (right / older side). Items arrive newest-first
            // within the batch, all older than existing items — correct order.
            items.append(contentsOf: newItems)
        } else {
            hasMoreOlder = false
        }
        isLoadingMore = false
    }
}
