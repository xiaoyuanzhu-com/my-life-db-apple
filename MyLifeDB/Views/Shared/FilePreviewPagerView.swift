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
    @State private var currentIndex: Int
    @State private var isLoadingMore = false

    private let hasMoreOlder: Bool
    private let loadMore: () async -> [PreviewItem]

    init(context: FilePreviewPagerContext, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.hasMoreOlder = context.hasMoreOlder
        self.loadMore = context.loadMore
        self._items = State(initialValue: context.items)
        self._currentIndex = State(initialValue: context.startIndex)
    }

    var body: some View {
        #if os(macOS)
        // macOS: no page-style TabView, fall back to single file viewer
        if let item = items[safe: currentIndex] {
            FileViewerView(filePath: item.path, fileName: item.name, onDismiss: onDismiss)
        }
        #else
        TabView(selection: $currentIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let file = item.file {
                    FileViewerView(file: file, onDismiss: onDismiss)
                        .tag(index)
                } else {
                    FileViewerView(filePath: item.path, fileName: item.name, onDismiss: onDismiss)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .onChange(of: currentIndex) { _, newIndex in
            if newIndex >= items.count - 3 && hasMoreOlder && !isLoadingMore {
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

// MARK: - Safe Collection Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
