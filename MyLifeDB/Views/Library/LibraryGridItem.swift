//
//  LibraryGridItem.swift
//  MyLifeDB
//
//  A single grid cell in the library browser.
//  Shows a file type icon, filename, and file size.
//

import SwiftUI

struct LibraryGridItem: View {

    let node: FileTreeNode

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: node.systemImage)
                .font(.system(size: 36))
                .foregroundStyle(iconColor)
                .frame(height: 44)

            Text(node.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            if let size = node.formattedSize {
                Text(size)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if node.isFolder {
                // Show child count hint for folders
                if let children = node.children {
                    Text("\(children.count) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformGray6.opacity(0.6))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Icon Color

    private var iconColor: Color {
        if node.isFolder { return .blue }
        guard let ext = node.fileExtension else { return .gray }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "svg", "tiff", "bmp":
            return .green
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return .purple
        case "mp3", "wav", "m4a", "aac", "ogg", "flac":
            return .pink
        case "pdf":
            return .red
        case "md", "txt":
            return .orange
        case "json", "xml", "yaml", "yml", "csv":
            return .teal
        case "swift", "go", "py", "js", "ts", "tsx", "jsx", "html", "css":
            return .indigo
        case "zip", "tar", "gz", "rar", "7z":
            return .brown
        default:
            return .gray
        }
    }
}
