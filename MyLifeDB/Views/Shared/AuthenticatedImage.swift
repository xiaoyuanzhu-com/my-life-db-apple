//
//  AuthenticatedImage.swift
//  MyLifeDB
//
//  Image view that loads from the backend with auth headers.
//  AsyncImage doesn't support custom headers, so this fetches
//  the data via URLSession and displays it as a SwiftUI Image.
//

import SwiftUI

struct AuthenticatedImage: View {
    let path: String

    @State private var imageData: Data?
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
                if let data = imageData {
                    #if os(iOS)
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        failedView
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        failedView
                    }
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

        var request = URLRequest(url: url)
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            imageData = data
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}

/// Loads images from the sqlar endpoint with auth headers.
struct AuthenticatedSqlarImage: View {
    let path: String

    @State private var imageData: Data?
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
                if let data = imageData {
                    #if os(iOS)
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
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

        var request = URLRequest(url: url)
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            imageData = data
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }
}
