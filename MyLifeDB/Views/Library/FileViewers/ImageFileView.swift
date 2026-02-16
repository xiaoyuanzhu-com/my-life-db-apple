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

    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

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
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let delta = value.magnification / lastScale
                            lastScale = value.magnification
                            scale = min(max(scale * delta, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale <= 1.0 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .conditionalPanGesture(
                    isActive: scale > 1.0,
                    offset: $offset,
                    lastOffset: $lastOffset
                )
        } else {
            ContentUnavailableView("Invalid Image", systemImage: "photo")
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let delta = value.magnification / lastScale
                            lastScale = value.magnification
                            scale = min(max(scale * delta, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale <= 1.0 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
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

// MARK: - Conditional Pan Gesture

/// Only attaches the DragGesture when active, so that TabView page
/// swiping is not blocked at 1x zoom.
private struct ConditionalPanGestureModifier: ViewModifier {
    let isActive: Bool
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    func body(content: Content) -> some View {
        if isActive {
            content.simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
        } else {
            content
        }
    }
}

private extension View {
    func conditionalPanGesture(
        isActive: Bool,
        offset: Binding<CGSize>,
        lastOffset: Binding<CGSize>
    ) -> some View {
        modifier(ConditionalPanGestureModifier(
            isActive: isActive,
            offset: offset,
            lastOffset: lastOffset
        ))
    }
}
