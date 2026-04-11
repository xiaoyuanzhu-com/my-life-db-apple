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

    var body: some View {
        let columns = distributeIntoColumns(posts, count: columnCount)

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
    }

    // MARK: - Column Distribution

    /// Distribute posts across columns, balancing estimated heights.
    /// Images get more height than text-only posts.
    private func distributeIntoColumns(_ posts: [ExplorePost], count: Int) -> [[ExplorePost]] {
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

    private func estimatedHeight(for post: ExplorePost) -> CGFloat {
        var height: CGFloat = 50 // base (title + author + padding)

        if post.hasMedia {
            height += 180 // image/video placeholder
        }

        return height
    }
}
