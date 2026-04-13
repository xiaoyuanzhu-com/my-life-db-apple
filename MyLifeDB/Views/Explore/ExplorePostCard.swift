//
//  ExplorePostCard.swift
//  MyLifeDB
//
//  Card component for a single Explore post in the masonry grid.
//  Shows cover image, title, content preview, tags, and author.
//

import SwiftUI

struct ExplorePostCard: View {

    let post: ExplorePost

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover media
            if let coverPath = post.coverImagePath {
                ZStack(alignment: .topTrailing) {
                    ExploreCardImage(path: coverPath)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 12,
                            topTrailingRadius: 12
                        ))

                    // Multi-image badge
                    if post.imageCount > 1 {
                        Text("\(post.imageCount)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }

                    // Video play icon
                    if post.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            // Content area — compact: title + author only
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(post.author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Bucketed Card Image

/// Loads an image and renders it cropped to one of 3 aspect ratio buckets
/// (3:4 portrait, 1:1 square, 4:3 landscape) for a consistent masonry grid.
private struct ExploreCardImage: View {

    let path: String

    @State private var image: FileCache.Image?
    @State private var loadState: LoadState = .loading
    @State private var aspectRatio: CGFloat = 3.0 / 4.0 // default: portrait

    private enum LoadState {
        case loading, loaded, failed
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                    ProgressView()
                }
                .aspectRatio(aspectRatio, contentMode: .fit)

            case .loaded:
                if let image {
                    GeometryReader { geo in
                        #if os(iOS) || os(visionOS)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        #elseif os(macOS)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        #endif
                    }
                    .aspectRatio(aspectRatio, contentMode: .fit)
                } else {
                    failedView
                }

            case .failed:
                failedView
            }
        }
        .task(id: path) {
            await loadImage()
        }
    }

    private var failedView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func loadImage() async {
        loadState = .loading
        let url = APIClient.shared.rawFileURL(path: path)

        do {
            let loaded = try await FileCache.shared.image(for: url)
            image = loaded
            aspectRatio = bucketAspectRatio(for: loaded)
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    /// Bucket the image's natural aspect ratio into 3:4, 1:1, or 4:3.
    private func bucketAspectRatio(for img: FileCache.Image) -> CGFloat {
        #if os(iOS) || os(visionOS)
        let w = img.size.width
        let h = img.size.height
        #elseif os(macOS)
        let w = img.size.width
        let h = img.size.height
        #endif

        guard h > 0 else { return 3.0 / 4.0 }
        let ratio = w / h

        if ratio > 1.1 { return 4.0 / 3.0 }    // landscape
        if ratio > 0.85 { return 1.0 }           // square
        return 3.0 / 4.0                          // portrait
    }
}

// MARK: - Flow Layout for Tags

/// Simple horizontal flow layout that wraps to next line.
struct FlowLayout: Layout {

    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
