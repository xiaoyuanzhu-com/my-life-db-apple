//
//  FallbackCard.swift
//  MyLifeDB
//
//  Card component for unknown file types.
//  Shows file icon, name, and size.
//

import SwiftUI

struct FallbackCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            // File type icon
            Image(systemName: iconName)
                .font(.title)
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if let mimeType = item.mimeType {
                        Text(mimeType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let size = item.formattedSize {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 280)
    }

    private var iconName: String {
        if item.isFolder {
            return "folder.fill"
        }

        guard let mimeType = item.mimeType else {
            return "doc"
        }

        if mimeType.hasPrefix("video/") {
            return "video.fill"
        } else if mimeType.hasPrefix("audio/") {
            return "waveform"
        } else if mimeType == "application/pdf" {
            return "doc.richtext.fill"
        } else if mimeType.contains("zip") || mimeType.contains("archive") {
            return "doc.zipper"
        } else if mimeType.contains("word") || mimeType.contains("document") {
            return "doc.text.fill"
        } else if mimeType.contains("sheet") || mimeType.contains("excel") {
            return "tablecells.fill"
        } else if mimeType.contains("presentation") || mimeType.contains("powerpoint") {
            return "slider.horizontal.below.rectangle"
        }

        return "doc"
    }

    private var iconColor: Color {
        if item.isFolder {
            return .blue
        }

        guard let mimeType = item.mimeType else {
            return .gray
        }

        if mimeType.hasPrefix("video/") {
            return .purple
        } else if mimeType.hasPrefix("audio/") {
            return .pink
        } else if mimeType == "application/pdf" {
            return .red
        } else if mimeType.contains("zip") || mimeType.contains("archive") {
            return .brown
        } else if mimeType.contains("word") || mimeType.contains("document") {
            return .blue
        } else if mimeType.contains("sheet") || mimeType.contains("excel") {
            return .green
        } else if mimeType.contains("presentation") || mimeType.contains("powerpoint") {
            return .orange
        }

        return .gray
    }
}

#Preview {
    VStack(spacing: 16) {
        FallbackCard(item: InboxItem(
            path: "inbox/document.pdf",
            name: "Annual Report 2024.pdf",
            isFolder: false,
            size: 5_678_901,
            mimeType: "application/pdf",
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

        FallbackCard(item: InboxItem(
            path: "inbox/archive.zip",
            name: "project-backup.zip",
            isFolder: false,
            size: 123_456_789,
            mimeType: "application/zip",
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

        FallbackCard(item: InboxItem(
            path: "inbox/folder",
            name: "My Documents",
            isFolder: true,
            size: nil,
            mimeType: nil,
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
