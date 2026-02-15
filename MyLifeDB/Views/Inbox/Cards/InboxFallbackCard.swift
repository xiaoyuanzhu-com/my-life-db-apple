//
//  InboxFallbackCard.swift
//  MyLifeDB
//
//  Fallback card for items with unrecognized content types.
//  Shows a generic file icon with name and size.
//

import SwiftUI

struct InboxFallbackCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let mime = item.mimeType {
                        Text(mime)
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
        .frame(maxWidth: 320)
    }
}
