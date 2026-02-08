#if LEGACY_NATIVE_VIEWS
//
//  ImageCard.swift
//  MyLifeDB
//
//  Card component for displaying images inline.
//  Uses AsyncImage to load from backend API.
//

import SwiftUI

struct ImageCard: View {
    let item: InboxItem

    /// Maximum height for the image
    private let maxHeight: CGFloat = 320

    /// Maximum width for the image
    private let maxWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            AsyncImage(url: imageURL) { phase in
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

            // Footer with filename
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

    private var imageURL: URL {
        APIClient.shared.rawFileURL(path: item.path)
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

#Preview {
    VStack(spacing: 16) {
        ImageCard(item: InboxItem(
            path: "inbox/photo.jpg",
            name: "vacation-photo.jpg",
            isFolder: false,
            size: 2_456_789,
            mimeType: "image/jpeg",
            hash: nil,
            modifiedAt: "2024-01-15T10:30:00Z",
            createdAt: "2024-01-15T10:30:00Z",
            digests: [],
            textPreview: nil,
            screenshotSqlar: nil,
            isPinned: false
        ))
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    .padding()
    .background(Color.platformGroupedBackground)
}

#endif // LEGACY_NATIVE_VIEWS
