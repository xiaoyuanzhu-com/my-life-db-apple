//
//  ExploreMasonryGrid.swift
//  MyLifeDB
//
//  Masonry (waterfall) layout for Explore posts.
//  Distributes posts across columns to minimize height difference.
//

import SwiftUI

struct ExploreMasonryGrid: View {

    let posts: [ExplorePost]
    let onPostTap: (ExplorePost) -> Void

    #if os(macOS)
    private let columnCount = 4
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var columnCount: Int {
        sizeClass == .regular ? 3 : 2
    }
    #endif

    // Memoized column distribution — only recomputed when posts or column count changes.
    @State private var columns: [[ExplorePost]] = []
    @State private var cachedFingerprint = ""

    /// Cheap proxy for change detection: catches pagination (count), refresh (ids),
    /// and rotation (column count) without comparing the full array.
    private var postsFingerprint: String {
        "\(columnCount)|\(posts.count)|\(posts.first?.id ?? "")|\(posts.last?.id ?? "")"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<columns.count, id: \.self) { colIndex in
                LazyVStack(spacing: 10) {
                    ForEach(columns[colIndex]) { post in
                        ExplorePostCard(post: post)
                            .onTapGesture { onPostTap(post) }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear { recomputeIfNeeded() }
        .onChange(of: postsFingerprint) { _, _ in recomputeIfNeeded() }
    }

    // MARK: - Column Distribution

    private func recomputeIfNeeded() {
        let fp = postsFingerprint
        guard fp != cachedFingerprint else { return }
        cachedFingerprint = fp
        columns = Self.distributeIntoColumns(posts, count: columnCount)
    }

    /// Distribute posts across columns, balancing estimated heights.
    static func distributeIntoColumns(_ posts: [ExplorePost], count: Int) -> [[ExplorePost]] {
        var columns = Array(repeating: [ExplorePost](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)

        for post in posts {
            // Find the shortest column
            let minIndex = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0

            columns[minIndex].append(post)
            heights[minIndex] += estimatedHeight(for: post)
        }

        return columns
    }

    private static func estimatedHeight(for post: ExplorePost) -> CGFloat {
        var height: CGFloat = 50 // base (title + author + padding)

        if post.hasMedia {
            height += 180 // image/video placeholder
        }

        return height
    }
}
