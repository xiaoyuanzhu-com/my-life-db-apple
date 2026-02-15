//
//  InboxImageCard.swift
//  MyLifeDB
//
//  Card component for displaying images inline.
//  Uses AsyncImage to load from backend API.
//

import SwiftUI

struct InboxImageCard: View {
    let item: InboxItem

    private let maxHeight: CGFloat = 320
    private let maxWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: APIClient.shared.rawFileURL(path: item.path)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                case .failure:
                    errorView

                case .empty:
                    loadingView

                @unknown default:
                    loadingView
                }
            }

            HStack(spacing: 8) {
                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: maxWidth + 24, alignment: .leading)
    }

    private var loadingView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
            ProgressView()
        }
        .frame(width: 200, height: 150)
    }

    private var errorView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Failed to load")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 150)
    }
}
