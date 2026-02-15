//
//  InboxPinnedBar.swift
//  MyLifeDB
//
//  Horizontal scrolling bar showing pinned inbox items.
//  Tap to navigate to the item in the feed.
//

import SwiftUI

struct InboxPinnedBar: View {
    let items: [PinnedItem]
    let onTap: (PinnedItem) -> Void
    let onUnpin: (PinnedItem) -> Void

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        pinnedTag(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func pinnedTag(_ item: PinnedItem) -> some View {
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
