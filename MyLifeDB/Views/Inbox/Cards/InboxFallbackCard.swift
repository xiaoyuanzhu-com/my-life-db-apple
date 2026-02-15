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
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            Text(item.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 320)
    }
}
