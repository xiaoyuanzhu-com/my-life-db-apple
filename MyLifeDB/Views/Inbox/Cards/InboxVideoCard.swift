//
//  InboxVideoCard.swift
//  MyLifeDB
//
//  Card component for displaying video items.
//  Shows a thumbnail placeholder with play icon.
//

import SwiftUI

struct InboxVideoCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: 120, height: 68)

                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 320)
    }
}
