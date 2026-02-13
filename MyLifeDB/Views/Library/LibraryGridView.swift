//
//  LibraryGridView.swift
//  MyLifeDB
//
//  Grid layout for library folder contents.
//  Uses LazyVGrid with adaptive columns, similar to iOS Files app.
//

import SwiftUI

struct LibraryGridView: View {

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
                    NavigationLink(value: destination(for: node, fullPath: fullPath)) {
                        LibraryGridItem(node: node)
                    }
                    .buttonStyle(.plain)
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

    private func destination(for node: FileTreeNode, fullPath: String) -> LibraryDestination {
        if node.isFolder {
            return .folder(path: fullPath, name: node.name)
        } else {
            return .file(path: fullPath, name: node.name)
        }
    }
}
