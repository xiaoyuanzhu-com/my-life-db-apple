//
//  ImageFileView.swift
//  MyLifeDB
//
//  Native image viewer with pinch-to-zoom and double-tap zoom.
//  Fetches image data via authenticated API (AsyncImage doesn't send auth headers).
//

import SwiftUI

struct ImageFileView: View {

    let path: String
    var onDismiss: (() -> Void)?

    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        Group {
            if let data = imageData {
                imageContent(data: data)
            } else if isLoading {
                ProgressView("Loading image...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Failed to Load Image",
                    systemImage: "photo",
                    description: Text(error?.localizedDescription ?? "Unknown error")
                )
            }
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(data: Data) -> some View {
        #if os(iOS) || os(visionOS)
        if let uiImage = UIImage(data: data) {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: geometry.size.width * scale,
                            height: geometry.size.height * scale
                        )
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height
                        )
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let delta = value.magnification / lastScale
                            lastScale = value.magnification
                            scale = min(max(scale * delta, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if scale > 1.1 {
                            scale = 1.0
                        } else {
                            scale = 2.5
                        }
                    }
                }
                .onTapGesture(count: 1) {
                    onDismiss?()
                }
            }
        } else {
            ContentUnavailableView("Invalid Image", systemImage: "photo")
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
            }
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scale = scale > 1.1 ? 1.0 : 2.5
                }
            }
            .onTapGesture(count: 1) {
                onDismiss?()
            }
        } else {
            ContentUnavailableView("Invalid Image", systemImage: "photo")
        }
        #endif
    }

    // MARK: - Data Fetching

    private func loadImage() async {
        isLoading = true
        error = nil

        do {
            let url = APIClient.shared.rawFileURL(path: path)
            imageData = try await FileCache.shared.data(for: url)
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
