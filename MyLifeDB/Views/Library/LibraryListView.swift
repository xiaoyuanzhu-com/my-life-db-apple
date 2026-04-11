//
//  LibraryListView.swift
//  MyLifeDB
//
//  List layout for library folder contents.
//  Shows icon and filename per row.
//

import SwiftUI

struct LibraryListView: View {

    @Environment(\.openFilePreview) private var openFilePreview
    @Environment(\.previewNamespace) private var previewNamespace

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
                        openFilePreview?(fullPath, node.name, nil, nil)
                    } label: {
                        LibraryListRow(node: node)
                    }
                    .buttonStyle(.plain)
                    .previewSource(
                        path: fullPath,
                        namespace: previewNamespace
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

            Text(node.name)
                .font(.body)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Icon Color

    private var iconColor: Color {
        node.isFolder ? .blue : .secondary
    }
}
