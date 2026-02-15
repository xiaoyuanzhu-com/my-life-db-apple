//
//  LibraryListView.swift
//  MyLifeDB
//
//  List layout for library folder contents.
//  Shows icon, filename, size, and modification date per row.
//

import SwiftUI

struct LibraryListView: View {

    @Environment(\.openFilePreview) private var openFilePreview
    @Environment(\.previewNamespace) private var previewNamespace
    @Environment(\.activePreviewPath) private var activePreviewPath

    let children: [FileTreeNode]
    let folderPath: String

    var body: some View {
        List {
            ForEach(children) { node in
                let fullPath = buildFullPath(for: node)
                if node.isFolder {
                    NavigationLink(value: LibraryDestination.folder(path: fullPath, name: node.name)) {
                        LibraryListRow(node: node)
                    }
                } else {
                    Button {
                        openFilePreview?(fullPath, node.name, nil)
                    } label: {
                        LibraryListRow(node: node)
                    }
                    .buttonStyle(.plain)
                    .previewSource(
                        path: fullPath,
                        namespace: previewNamespace,
                        activePreviewPath: activePreviewPath
                    )
                }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        #else
        .listStyle(.sidebar)
        #endif
    }

    // MARK: - Helpers

    private func buildFullPath(for node: FileTreeNode) -> String {
        folderPath.isEmpty ? node.name : "\(folderPath)/\(node.name)"
    }
}

// MARK: - List Row

struct LibraryListRow: View {

    let node: FileTreeNode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.systemImage)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let size = node.formattedSize {
                        Text(size)
                    }

                    if let date = node.modifiedDate {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(date, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
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
        case "swift", "go", "py", "js", "ts", "tsx", "jsx", "html", "css":
            return .indigo
        default:
            return .gray
        }
    }
}
