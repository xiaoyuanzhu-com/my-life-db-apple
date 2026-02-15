//
//  InboxFallbackCard.swift
//  MyLifeDB
//
//  Fallback card for items with unrecognized content types.
//

import SwiftUI

struct InboxFallbackCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Spacer(minLength: 8)

            Image(systemName: "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
