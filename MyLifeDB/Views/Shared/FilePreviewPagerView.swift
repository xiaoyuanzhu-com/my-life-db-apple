//
//  FilePreviewPagerView.swift
//  MyLifeDB
//
//  Horizontal pager for swiping between media files (images and videos)
//  in the inbox file preview. Uses a simple ScrollView with paging so
//  each item sits side by side at full width. Non-media files are
//  excluded from the pager.
//

import SwiftUI

struct FilePreviewPagerView: View {

    let onDismiss: () -> Void

    @State private var items: [PreviewItem]
    @State private var currentID: String?
    @State private var isLoadingMore = false

    private let hasMoreOlder: Bool
    private let loadMore: () async -> [PreviewItem]

    init(context: FilePreviewPagerContext, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.hasMoreOlder = context.hasMoreOlder
        self.loadMore = context.loadMore
        self._items = State(initialValue: context.items)
        // Use the item's stable ID (path) for selection, not an Int index
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
            // Load more when approaching the end of the list
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
            items.append(contentsOf: newItems)
        }
        isLoadingMore = false
    }
}
