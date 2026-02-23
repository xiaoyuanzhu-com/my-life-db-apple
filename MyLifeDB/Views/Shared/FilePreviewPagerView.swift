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

    /// Maximum number of items to keep in the pager. When loading older
    /// items pushes the array past this limit, the newest items (at the
    /// end, i.e. rightmost) are trimmed. This keeps memory bounded while
    /// preserving the older items the user is actively swiping toward.
    private static let maxItemCount = 100

    // Items in chronological order (oldest first / leftmost).
    // Reversed from the feed's newest-first order.
    @State private var items: [PreviewItem]
    @State private var currentID: String?
    @State private var isLoadingMore = false
    @State private var hasMoreOlder: Bool
    /// Active prefetch tasks — limited to avoid spawning unbounded concurrent requests.
    @State private var activePrefetchTasks = 0
    private static let maxConcurrentPrefetch = 2

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

    /// Prefetch adjacent items so swiping feels instant.
    /// - Images: warm raw data into FileCache
    /// - All items without a FileRecord: fetch metadata so FileViewerView skips its own fetch
    ///
    /// Throttled to at most `maxConcurrentPrefetch` in-flight requests to
    /// avoid spawning unbounded concurrent tasks during rapid scrolling.
    private func prefetchAdjacentItems(around id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        for delta in [-1, 1] {
            let adjacent = idx + delta
            guard adjacent >= 0 && adjacent < items.count else { continue }
            let item = items[adjacent]
            guard activePrefetchTasks < Self.maxConcurrentPrefetch else { return }

            // Prefetch file metadata if missing (eliminates a network roundtrip on swipe)
            if item.file == nil {
                activePrefetchTasks += 1
                Task {
                    defer { activePrefetchTasks -= 1 }
                    guard let response = try? await APIClient.shared.library.getFileInfo(path: item.path) else { return }
                    if let i = items.firstIndex(where: { $0.id == item.id }) {
                        items[i].file = response.file
                    }
                }
            }

            // Prefetch raw image data into FileCache
            if item.isLikelyImage {
                activePrefetchTasks += 1
                let url = APIClient.shared.rawFileURL(path: item.path)
                Task {
                    defer { activePrefetchTasks -= 1 }
                    _ = try? await FileCache.shared.data(for: url)
                }
            }
        }
    }

    private func loadMoreItems() async {
        isLoadingMore = true
        let newItems = await loadMore()
        if !newItems.isEmpty {
            // Prepend to the start (left / older side).
            // New items arrive newest-first from the API, reverse to oldest-first.
            items.insert(contentsOf: newItems.reversed(), at: 0)

            // Trim the newest (rightmost) items if we've exceeded the cap.
            // The user is scrolling left toward older items, so the right
            // end is least relevant.
            if items.count > Self.maxItemCount {
                items = Array(items.prefix(Self.maxItemCount))
            }
        } else {
            hasMoreOlder = false
        }
        isLoadingMore = false
    }
}
