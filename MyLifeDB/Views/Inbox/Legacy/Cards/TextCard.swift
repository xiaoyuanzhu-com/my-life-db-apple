#if LEGACY_NATIVE_VIEWS
//
//  TextCard.swift
//  MyLifeDB
//
//  Card component for displaying text/markdown content.
//  Shows preview text with truncation at 20 lines.
//

import SwiftUI

struct TextCard: View {
    let item: InboxItem
    private let maxLines = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text preview
            if let preview = item.textPreview, !preview.isEmpty {
                Text(preview)
                    .font(.body)
                    .lineLimit(maxLines)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            } else {
                Text("No content")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            // Footer with file info
            HStack(spacing: 8) {
                // File extension badge
                if let ext = fileExtension {
                    Text(ext.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                // Size
                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var fileExtension: String? {
        let name = item.name
        guard let dotIndex = name.lastIndex(of: ".") else { return nil }
        let ext = String(name[name.index(after: dotIndex)...])
        return ext.isEmpty ? nil : ext
    }
}

#Preview {
    VStack(spacing: 16) {
        TextCard(item: InboxItem(
            path: "inbox/note.md",
            name: "note.md",
            isFolder: false,
            size: 1234,
            mimeType: "text/markdown",
            hash: nil,
            modifiedAt: "2024-01-15T10:30:00Z",
            createdAt: "2024-01-15T10:30:00Z",
            digests: [],
            textPreview: "# Hello World\n\nThis is a sample note with some markdown content.\n\n- Item 1\n- Item 2\n- Item 3",
            screenshotSqlar: nil,
            isPinned: false
        ))
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

        TextCard(item: InboxItem(
            path: "inbox/empty.txt",
            name: "empty.txt",
            isFolder: false,
            size: 0,
            mimeType: "text/plain",
            hash: nil,
            modifiedAt: "2024-01-15T10:30:00Z",
            createdAt: "2024-01-15T10:30:00Z",
            digests: [],
            textPreview: nil,
            screenshotSqlar: nil,
            isPinned: false
        ))
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    .padding()
    .background(Color.platformGroupedBackground)
}

#endif // LEGACY_NATIVE_VIEWS
