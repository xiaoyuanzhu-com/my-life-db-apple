//
//  FilePreviewPagerView.swift
//  MyLifeDB
//
//  Horizontal pager for swiping between media files (images and videos)
//  in the inbox file preview. Uses TabView with page style for native
//  iOS swipe physics. Non-media files are excluded from the pager.
//

import SwiftUI

struct FilePreviewPagerView: View {

    let onDismiss: () -> Void

    @State private var items: [PreviewItem]
    @State private var currentID: String
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
        // macOS: no page-style TabView, fall back to single file viewer
        if let item = items.first(where: { $0.id == currentID }) {
            FileViewerView(filePath: item.path, fileName: item.name, onDismiss: onDismiss)
        }
        #else
        TabView(selection: $currentID) {
            ForEach(items) { item in
                if let file = item.file {
                    FileViewerView(file: file, onDismiss: onDismiss)
                        .tag(item.id)
                } else {
                    FileViewerView(filePath: item.path, fileName: item.name, onDismiss: onDismiss)
                        .tag(item.id)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: currentID) { _, _ in
            // Load more when approaching the end of the list
            if let idx = items.firstIndex(where: { $0.id == currentID }),
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
