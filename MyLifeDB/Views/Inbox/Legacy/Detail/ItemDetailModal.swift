#if LEGACY_NATIVE_VIEWS
//
//  ItemDetailModal.swift
//  MyLifeDB
//
//  Full-screen modal for viewing inbox item details.
//  Supports swipe navigation between items.
//

import SwiftUI

struct ItemDetailModal: View {
    /// The item to display
    let item: InboxItem

    /// All items for navigation
    let allItems: [InboxItem]

    /// Dismiss action
    @Environment(\.dismiss) private var dismiss

    /// Current item index
    @State private var currentIndex: Int

    /// Show digests panel
    @State private var showDigests = false

    init(item: InboxItem, allItems: [InboxItem]) {
        self.item = item
        self.allItems = allItems
        // Find initial index (items are in API order: newest first)
        _currentIndex = State(initialValue: allItems.firstIndex(of: item) ?? 0)
    }

    private var currentItem: InboxItem {
        guard currentIndex >= 0 && currentIndex < allItems.count else {
            return item
        }
        return allItems[currentIndex]
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                    ItemDetailContent(item: item)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .navigationTitle(currentItem.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            downloadItem(currentItem)
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }

                        Button {
                            shareItem(currentItem)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button {
                            showDigests = true
                        } label: {
                            Label("Digests", systemImage: "brain")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showDigests) {
                DigestsPanel(digests: currentItem.digests)
            }
        }
    }

    private func downloadItem(_ item: InboxItem) {
        // Download functionality - platform specific
        print("Download: \(item.path)")
    }

    private func shareItem(_ item: InboxItem) {
        // Share functionality - platform specific
        print("Share: \(item.path)")
    }
}

// MARK: - Item Detail Content

struct ItemDetailContent: View {
    let item: InboxItem

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Content based on type
                contentView

                // Metadata
                metadataSection
            }
            .padding()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if item.isImage {
            imageContent
        } else if item.isVideo {
            videoContent
        } else if let textPreview = item.textPreview, !textPreview.isEmpty {
            textContent(textPreview)
        } else {
            fallbackContent
        }
    }

    private var imageContent: some View {
        AsyncImage(url: APIClient.shared.rawFileURL(path: item.path)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

            case .failure:
                errorPlaceholder

            case .empty:
                ProgressView()
                    .frame(height: 200)

            @unknown default:
                EmptyView()
            }
        }
    }

    private var videoContent: some View {
        ZStack {
            // Thumbnail or screenshot
            if let screenshot = item.screenshotSqlar {
                AsyncImage(url: APIClient.shared.sqlarFileURL(path: screenshot)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.black
                }
            } else {
                Color.black
            }

            // Play button
            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func textContent(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.platformGray6)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fallbackContent: some View {
        VStack(spacing: 16) {
            Image(systemName: iconForItem)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(item.name)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let mimeType = item.mimeType {
                Text(mimeType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var errorPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Failed to load content")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            LabeledContent("Name", value: item.name)
            LabeledContent("Path", value: item.path)

            if let size = item.formattedSize {
                LabeledContent("Size", value: size)
            }

            if let mimeType = item.mimeType {
                LabeledContent("Type", value: mimeType)
            }

            LabeledContent("Created", value: formatDate(item.createdAt))
            LabeledContent("Modified", value: formatDate(item.modifiedAt))

            if item.isPinned {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                    Text("Pinned")
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color.platformGray6)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconForItem: String {
        if item.isFolder { return "folder.fill" }
        if item.isImage { return "photo" }
        if item.isVideo { return "video.fill" }

        guard let mimeType = item.mimeType else { return "doc" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType == "application/pdf" { return "doc.richtext.fill" }
        return "doc"
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else {
                return dateString
            }
            return formatDateOutput(date)
        }
        return formatDateOutput(date)
    }

    private func formatDateOutput(_ date: Date) -> String {
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .short
        return outputFormatter.string(from: date)
    }
}

// MARK: - Digests Panel

struct DigestsPanel: View {
    let digests: [Digest]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if digests.isEmpty {
                    ContentUnavailableView(
                        "No Digests",
                        systemImage: "brain",
                        description: Text("This item hasn't been processed yet")
                    )
                } else {
                    ForEach(digests) { digest in
                        DigestRow(digest: digest)
                    }
                }
            }
            .navigationTitle("Digests")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DigestRow: View {
    let digest: Digest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(digest.digesterDisplayName)
                    .font(.headline)

                Spacer()

                statusBadge
            }

            if let content = digest.content, !content.isEmpty {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            if let error = digest.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(digest.status.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch digest.status {
        case .pending, .todo: return .orange
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    ItemDetailModal(
        item: InboxItem(
            path: "inbox/note.md",
            name: "note.md",
            isFolder: false,
            size: 1234,
            mimeType: "text/markdown",
            hash: nil,
            modifiedAt: "2024-01-15T10:30:00Z",
            createdAt: "2024-01-15T10:30:00Z",
            digests: [
                Digest(
                    id: "1",
                    filePath: "inbox/note.md",
                    digester: "summary",
                    status: .completed,
                    content: "This is a summary of the note content.",
                    sqlarName: nil,
                    error: nil,
                    attempts: 1,
                    createdAt: "2024-01-15T10:30:00Z",
                    updatedAt: "2024-01-15T10:31:00Z"
                )
            ],
            textPreview: "# Hello World\n\nThis is a sample note.",
            screenshotSqlar: nil,
            isPinned: true
        ),
        allItems: []
    )
}

#endif // LEGACY_NATIVE_VIEWS
