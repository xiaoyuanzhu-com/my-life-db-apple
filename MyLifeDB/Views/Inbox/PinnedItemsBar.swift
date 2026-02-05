//
//  PinnedItemsBar.swift
//  MyLifeDB
//
//  Horizontal scrolling bar showing pinned inbox items.
//  Tap to navigate to the item in the feed.
//

import SwiftUI

struct PinnedItemsBar: View {
    /// Pinned items to display
    let items: [PinnedItem]

    /// Callback when a pinned item is tapped
    let onTap: (PinnedItem) -> Void

    /// Callback when unpin is requested
    let onUnpin: (PinnedItem) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        PinnedTag(item: item)
                            .onTapGesture {
                                onTap(item)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onUnpin(item)
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Pinned Tag

struct PinnedTag: View {
    let item: PinnedItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.caption2)
                .foregroundStyle(.orange)

            Text(item.displayText)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PinnedItemsBar(
            items: [
                PinnedItem(
                    path: "inbox/note1.md",
                    name: "note1.md",
                    pinnedAt: "2024-01-15T10:30:00Z",
                    displayText: "Remember to call mom",
                    cursor: "2024-01-15T10:30:00Z:inbox/note1.md"
                ),
                PinnedItem(
                    path: "inbox/todo.md",
                    name: "todo.md",
                    pinnedAt: "2024-01-14T08:00:00Z",
                    displayText: "Shopping list for weekend",
                    cursor: "2024-01-14T08:00:00Z:inbox/todo.md"
                ),
                PinnedItem(
                    path: "inbox/idea.md",
                    name: "idea.md",
                    pinnedAt: "2024-01-13T15:45:00Z",
                    displayText: "App feature idea",
                    cursor: "2024-01-13T15:45:00Z:inbox/idea.md"
                ),
            ],
            onTap: { item in print("Tapped: \(item.name)") },
            onUnpin: { item in print("Unpin: \(item.name)") }
        )
        .background(Color.platformBackground)

        PinnedItemsBar(
            items: [],
            onTap: { _ in },
            onUnpin: { _ in }
        )
        .background(Color.platformBackground)
    }
    .background(Color.platformGroupedBackground)
}
