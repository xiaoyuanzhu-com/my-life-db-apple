//
//  InboxTextCard.swift
//  MyLifeDB
//
//  Card component for displaying text/markdown content.
//  Shows preview text with truncation at 20 lines.
//

import SwiftUI

struct InboxTextCard: View {
    let item: InboxItem
    private let maxLines = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(spacing: 8) {
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
        guard let dotIndex = item.name.lastIndex(of: ".") else { return nil }
        let ext = String(item.name[item.name.index(after: dotIndex)...])
        return ext.isEmpty ? nil : ext
    }
}
