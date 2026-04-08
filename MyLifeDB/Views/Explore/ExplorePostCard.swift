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
                    AuthenticatedImage(path: coverPath)
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

            // Content area
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(post.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                // Content preview
                if let content = post.content, !content.isEmpty {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Tags
                if let tags = post.tags, !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Author + date
                HStack(spacing: 4) {
                    Text(post.author)
                        .font(.caption2)
                        .fontWeight(.medium)
                    Spacer()
                    Text(post.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
