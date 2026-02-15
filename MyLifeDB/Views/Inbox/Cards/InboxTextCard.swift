//
//  InboxTextCard.swift
//  MyLifeDB
//
//  Card component for displaying text/markdown content.
//  Simple: just the text content, matching web's text-card.tsx.
//

import SwiftUI

struct InboxTextCard: View {
    let item: InboxItem
    private let maxLines = 20

    var body: some View {
        Group {
            if let preview = item.textPreview, !preview.isEmpty {
                Text(preview)
                    .font(.body)
                    .lineLimit(maxLines)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            } else {
                Text("No content")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }
}
