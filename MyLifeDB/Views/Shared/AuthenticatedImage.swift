//
//  AuthenticatedImage.swift
//  MyLifeDB
//
//  Image view that loads from the backend with auth headers.
//  Uses ImageCache for two-tier caching (in-memory decoded + HTTP disk cache).
//

import SwiftUI

struct AuthenticatedImage: View {
    let path: String

    @State private var image: ImageCache.Image?
    @State private var loadState: LoadState = .loading

    private enum LoadState {
        case loading, loaded, failed
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                    ProgressView()
                }
                .frame(minWidth: 100, minHeight: 80)
                .aspectRatio(contentMode: .fit)

            case .loaded:
                if let image {
                    #if os(iOS) || os(visionOS)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    #elseif os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    #endif
                } else {
                    failedView
                }

            case .failed:
                failedView
            }
        }
        .task(id: path) {
            await loadImage()
        }
    }

    private var failedView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 90)
    }

    private func loadImage() async {
        loadState = .loading
        let url = APIClient.shared.rawFileURL(path: path)

        do {
            image = try await ImageCache.shared.image(for: url)
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}

/// Loads images from the sqlar endpoint with auth headers.
struct AuthenticatedSqlarImage: View {
    let path: String

    @State private var image: ImageCache.Image?
    @State private var loadState: LoadState = .loading

    private enum LoadState {
        case loading, loaded, failed
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                    ProgressView()
                }
                .frame(minWidth: 80, minHeight: 60)

            case .loaded:
                if let image {
                    #if os(iOS) || os(visionOS)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    #elseif os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    #endif
                }

            case .failed:
                documentIconFallback
            }
        }
        .task(id: path) {
            await loadImage()
        }
    }

    private var documentIconFallback: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
            .frame(width: 120, height: 100)
    }

    private func loadImage() async {
        loadState = .loading
        let url = APIClient.shared.sqlarFileURL(path: path)

        do {
            image = try await ImageCache.shared.image(for: url)
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}
