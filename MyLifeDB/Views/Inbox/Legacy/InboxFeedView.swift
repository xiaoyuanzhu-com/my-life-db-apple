#if LEGACY_NATIVE_VIEWS
//
//  InboxFeedView.swift
//  MyLifeDB
//
//  Chat-style feed for displaying inbox items.
//  Items are displayed newest at bottom, oldest at top.
//  Scroll up to load older items.
//

import SwiftUI

struct InboxFeedView: View {
    /// Items to display (API order: newest first)
    let items: [InboxItem]

    /// Whether currently loading more items
    let isLoadingMore: Bool

    /// Whether there are older items to load
    let hasOlderItems: Bool

    /// Callback to load more items
    let onLoadMore: () -> Void

    /// Callback when item is tapped
    let onItemTap: (InboxItem) -> Void

    /// Callback when item is deleted
    let onItemDelete: (InboxItem) -> Void

    /// Callback to pin/unpin item
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
                // Auto-scroll to bottom when new items arrive
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
            // Timestamp
            TimestampView(dateString: item.createdAt)

            // Card
            InboxItemCard(item: item) {
                onItemTap(item)
            }
            .contextMenu {
                contextMenuContent(for: item)
            }
            #if os(iOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onItemDelete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            #endif

            // Pin indicator
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

        if let textPreview = item.textPreview, !textPreview.isEmpty {
            Button {
                copyToClipboard(textPreview)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }

        Button {
            shareItem(item)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
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

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func shareItem(_ item: InboxItem) {
        // Share functionality will be implemented via share sheet
        // For now, copy the path to clipboard
        copyToClipboard(item.path)
    }
}

// MARK: - Preview

#Preview {
    InboxFeedView(
        items: [
            InboxItem(
                path: "inbox/note1.md",
                name: "note1.md",
                isFolder: false,
                size: 1234,
                mimeType: "text/markdown",
                hash: nil,
                modifiedAt: "2024-01-15T08:30:00Z",
                createdAt: "2024-01-15T08:30:00Z",
                digests: [],
                textPreview: "First note in the inbox",
                screenshotSqlar: nil,
                isPinned: true
            ),
            InboxItem(
                path: "inbox/photo.jpg",
                name: "photo.jpg",
                isFolder: false,
                size: 2_456_789,
                mimeType: "image/jpeg",
                hash: nil,
                modifiedAt: "2024-01-15T09:30:00Z",
                createdAt: "2024-01-15T09:30:00Z",
                digests: [],
                textPreview: nil,
                screenshotSqlar: nil,
                isPinned: false
            ),
            InboxItem(
                path: "inbox/note2.md",
                name: "note2.md",
                isFolder: false,
                size: 567,
                mimeType: "text/markdown",
                hash: nil,
                modifiedAt: "2024-01-15T10:30:00Z",
                createdAt: "2024-01-15T10:30:00Z",
                digests: [],
                textPreview: "Latest thought: This is the most recent item in the inbox.",
                screenshotSqlar: nil,
                isPinned: false
            ),
        ],
        isLoadingMore: false,
        hasOlderItems: true,
        onLoadMore: { print("Load more") },
        onItemTap: { item in print("Tapped: \(item.name)") },
        onItemDelete: { item in print("Delete: \(item.name)") },
        onItemPin: { item in print("Pin: \(item.name)") }
    )
    .background(Color.platformGroupedBackground)
}

#endif // LEGACY_NATIVE_VIEWS
