//
//  InboxAudioCard.swift
//  MyLifeDB
//
//  Card component for displaying audio items.
//  Shows play icon with waveform placeholder.
//

import SwiftUI

struct InboxAudioCard: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.pink)

            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.pink.opacity(0.4))
                        .frame(width: 3, height: CGFloat.random(in: 8...24))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 280)
    }
}
