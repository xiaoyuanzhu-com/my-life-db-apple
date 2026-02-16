//
//  LibraryGridView.swift
//  MyLifeDB
//
//  Grid layout for library folder contents.
//  Uses LazyVGrid with adaptive columns, similar to iOS Files app.
//

import SwiftUI

struct LibraryGridView: View {

    @Environment(\.openFilePreview) private var openFilePreview
    @Environment(\.previewNamespace) private var previewNamespace

    let children: [FileTreeNode]
    let folderPath: String

    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(children) { node in
                    let fullPath = buildFullPath(for: node)
                    if node.isFolder {
                        NavigationLink(value: LibraryDestination.folder(path: fullPath, name: node.name)) {
                            LibraryGridItem(node: node)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            openFilePreview?(fullPath, node.name, nil)
                        } label: {
                            LibraryGridItem(node: node)
                        }
                        .buttonStyle(.plain)
                        .previewSource(
                            path: fullPath,
                            namespace: previewNamespace
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers

    private func buildFullPath(for node: FileTreeNode) -> String {
        folderPath.isEmpty ? node.name : "\(folderPath)/\(node.name)"
    }
}
