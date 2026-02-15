//
//  InboxFeedView.swift
//  MyLifeDB
//
//  Chat-style feed for displaying inbox items.
//  Items displayed oldest at top, newest at bottom.
//  Scroll up to load older items.
//

import SwiftUI

struct InboxFeedView: View {

    let items: [InboxItem]
    let isLoadingMore: Bool
    let hasOlderItems: Bool
    let onLoadMore: () -> Void
    let onItemDelete: (InboxItem) -> Void
    let onItemPin: (InboxItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: 16) {
                    // Load more section at top
                    if hasOlderItems {
                        loadMoreSection
                    }

                    // Items in reverse order (oldest first for chat layout)
                    ForEach(items.reversed()) { item in
                        itemView(for: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: items.count) { oldCount, newCount in
                if newCount > oldCount, let lastItem = items.first {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastItem.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Item View

    @ViewBuilder
    private func itemView(for item: InboxItem) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            InboxTimestampView(dateString: item.createdAt)

            NavigationLink(value: InboxDestination.file(path: item.path, name: item.name)) {
                InboxItemCard(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu {
                contextMenuContent(for: item)
            }

            if item.isPinned {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                    Text("Pinned")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuContent(for item: InboxItem) -> some View {
        Button {
            onItemPin(item)
        } label: {
            Label(
                item.isPinned ? "Unpin" : "Pin",
                systemImage: item.isPinned ? "pin.slash" : "pin"
            )
        }

        Divider()

        Button(role: .destructive) {
            onItemDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Load More

    private var loadMoreSection: some View {
        VStack(spacing: 8) {
            if isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
            } else {
                Button {
                    onLoadMore()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                        Text("Load older items")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
