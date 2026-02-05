//
//  InboxItemCard.swift
//  MyLifeDB
//
//  Card router that dispatches to the appropriate card type
//  based on the inbox item's content type.
//

import SwiftUI

struct InboxItemCard: View {
    let item: InboxItem

    /// Callback when card is tapped
    var onTap: (() -> Void)?

    var body: some View {
        cardContent
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                onTap?()
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch contentType {
        case .image:
            ImageCard(item: item)

        case .text:
            TextCard(item: item)

        case .video:
            VideoCard(item: item)

        case .audio:
            AudioCard(item: item)

        case .document:
            DocumentCard(item: item)

        case .fallback:
            FallbackCard(item: item)
        }
    }

    private var contentType: ContentType {
        // Check MIME type first
        if let mimeType = item.mimeType {
            if mimeType.hasPrefix("image/") {
                return .image
            }
            if mimeType.hasPrefix("video/") {
                return .video
            }
            if mimeType.hasPrefix("audio/") {
                return .audio
            }
            if mimeType.hasPrefix("text/") {
                return .text
            }
            if mimeType == "application/pdf" ||
               mimeType.contains("document") ||
               mimeType.contains("sheet") ||
               mimeType.contains("presentation") ||
               mimeType.contains("msword") ||
               mimeType.contains("excel") ||
               mimeType.contains("powerpoint") {
                return .document
            }
        }

        // Check file extension
        let ext = item.name.lowercased().split(separator: ".").last.map(String.init) ?? ""
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "svg":
            return .image
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return .video
        case "mp3", "m4a", "wav", "aac", "ogg", "flac", "wma":
            return .audio
        case "txt", "md", "markdown", "json", "xml", "html", "css", "js", "ts", "swift", "py", "go", "rs":
            return .text
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx":
            return .document
        default:
            break
        }

        // If has text preview, show as text
        if item.textPreview != nil && !(item.textPreview?.isEmpty ?? true) {
            return .text
        }

        return .fallback
    }

    private enum ContentType {
        case image
        case video
        case audio
        case text
        case document
        case fallback
    }
}

// MARK: - Placeholder Cards (to be implemented in Phase 2)

/// Placeholder for video card - will be enhanced with thumbnail
struct VideoCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: 120, height: 68)

                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 320)
    }
}

/// Placeholder for audio card - will be enhanced with waveform
struct AudioCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.pink)

            // Waveform placeholder
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.pink.opacity(0.4))
                        .frame(width: 3, height: CGFloat.random(in: 8...24))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 280)
    }
}

/// Placeholder for document card - will show screenshot thumbnail
struct DocumentCard: View {
    let item: InboxItem

    var body: some View {
        VStack(spacing: 8) {
            // Screenshot thumbnail or icon
            if let screenshotPath = item.screenshotSqlar {
                AsyncImage(url: APIClient.shared.sqlarFileURL(path: screenshotPath)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                    case .failure, .empty:
                        documentIconView

                    @unknown default:
                        documentIconView
                    }
                }
            } else {
                documentIconView
            }

            // File info
            HStack {
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 240)
    }

    private var documentIconView: some View {
        VStack(spacing: 8) {
            Image(systemName: documentIcon)
                .font(.system(size: 48))
                .foregroundStyle(documentColor)

            Text(fileExtension.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 100)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var documentIcon: String {
        switch fileExtension {
        case "pdf":
            return "doc.richtext.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "slider.horizontal.below.rectangle"
        default:
            return "doc.fill"
        }
    }

    private var documentColor: Color {
        switch fileExtension {
        case "pdf":
            return .red
        case "doc", "docx":
            return .blue
        case "xls", "xlsx":
            return .green
        case "ppt", "pptx":
            return .orange
        default:
            return .gray
        }
    }

    private var fileExtension: String {
        guard let dotIndex = item.name.lastIndex(of: ".") else { return "" }
        return String(item.name[item.name.index(after: dotIndex)...]).lowercased()
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            InboxItemCard(item: InboxItem(
                path: "inbox/note.md",
                name: "note.md",
                isFolder: false,
                size: 1234,
                mimeType: "text/markdown",
                hash: nil,
                modifiedAt: "2024-01-15T10:30:00Z",
                createdAt: "2024-01-15T10:30:00Z",
                digests: [],
                textPreview: "# Hello World\n\nThis is a test note.",
                screenshotSqlar: nil,
                isPinned: false
            ))

            InboxItemCard(item: InboxItem(
                path: "inbox/photo.jpg",
                name: "vacation.jpg",
                isFolder: false,
                size: 2_345_678,
                mimeType: "image/jpeg",
                hash: nil,
                modifiedAt: "2024-01-15T10:30:00Z",
                createdAt: "2024-01-15T10:30:00Z",
                digests: [],
                textPreview: nil,
                screenshotSqlar: nil,
                isPinned: false
            ))

            InboxItemCard(item: InboxItem(
                path: "inbox/video.mp4",
                name: "birthday-party.mp4",
                isFolder: false,
                size: 45_678_901,
                mimeType: "video/mp4",
                hash: nil,
                modifiedAt: "2024-01-15T10:30:00Z",
                createdAt: "2024-01-15T10:30:00Z",
                digests: [],
                textPreview: nil,
                screenshotSqlar: nil,
                isPinned: false
            ))

            InboxItemCard(item: InboxItem(
                path: "inbox/recording.m4a",
                name: "voice-memo.m4a",
                isFolder: false,
                size: 567_890,
                mimeType: "audio/mp4",
                hash: nil,
                modifiedAt: "2024-01-15T10:30:00Z",
                createdAt: "2024-01-15T10:30:00Z",
                digests: [],
                textPreview: nil,
                screenshotSqlar: nil,
                isPinned: false
            ))

            InboxItemCard(item: InboxItem(
                path: "inbox/report.pdf",
                name: "Q4-Report.pdf",
                isFolder: false,
                size: 3_456_789,
                mimeType: "application/pdf",
                hash: nil,
                modifiedAt: "2024-01-15T10:30:00Z",
                createdAt: "2024-01-15T10:30:00Z",
                digests: [],
                textPreview: nil,
                screenshotSqlar: nil,
                isPinned: false
            ))
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
