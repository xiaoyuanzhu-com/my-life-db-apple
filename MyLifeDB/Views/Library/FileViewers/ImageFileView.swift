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
    /// Called on single tap (used for dismiss). Double-tap is handled internally for zoom.
    var onTap: (() -> Void)?

    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero

    private let zoomTarget: CGFloat = 1.5
    private let doubleTapZoomInDuration: TimeInterval = 0.55
    private let doubleTapZoomOutDuration: TimeInterval = 0.28
    private let pinchResetDuration: TimeInterval = 0.24

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
                .background(GeometryReader { geo in Color.clear.preference(key: ViewSizeKey.self, value: geo.size) })
                .onPreferenceChange(ViewSizeKey.self) { viewSize = $0 }
                .highPriorityGesture(tapGesture)
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
                                withAnimation(.linear(duration: pinchResetDuration)) {
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
                .background(GeometryReader { geo in Color.clear.preference(key: ViewSizeKey.self, value: geo.size) })
                .onPreferenceChange(ViewSizeKey.self) { viewSize = $0 }
                .highPriorityGesture(tapGesture)
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
                                withAnimation(.linear(duration: pinchResetDuration)) {
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

    private var tapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .exclusively(before: SpatialTapGesture(count: 1))
            .onEnded { value in
                switch value {
                case .first(let doubleTap):
                    handleDoubleTap(at: doubleTap.location)
                case .second:
                    guard scale <= 1.0 else { return }
                    onTap?()
                }
            }
    }

    private func handleDoubleTap(at location: CGPoint) {
        if scale > 1.0 {
            lastOffset = .zero
            withAnimation(.linear(duration: doubleTapZoomOutDuration)) {
                scale = 1.0
                offset = .zero
            }
        } else {
            let targetOffset = zoomOffset(for: location, scale: zoomTarget)
            lastOffset = targetOffset
            withAnimation(.linear(duration: doubleTapZoomInDuration)) {
                scale = zoomTarget
                offset = targetOffset
            }
        }
    }

    private func zoomOffset(for location: CGPoint, scale: CGFloat) -> CGSize {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let xRatio = (location.x / viewSize.width) - 0.5
        let yRatio = (location.y / viewSize.height) - 0.5
        let rawOffset = CGSize(
            width: -xRatio * viewSize.width * (scale - 1),
            height: -yRatio * viewSize.height * (scale - 1)
        )

        let maxOffsetX = viewSize.width * (scale - 1) / 2
        let maxOffsetY = viewSize.height * (scale - 1) / 2

        return CGSize(
            width: min(max(rawOffset.width, -maxOffsetX), maxOffsetX),
            height: min(max(rawOffset.height, -maxOffsetY), maxOffsetY)
        )
    }
}

// MARK: - View Size Preference Key

private struct ViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Conditional Pan Gesture

/// Always attaches DragGesture, but only mutates offset while active.
/// Keeping one stable view tree avoids visual ghosting when scale animates
/// across the 1x threshold.
private struct ConditionalPanGestureModifier: ViewModifier {
    let isActive: Bool
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard isActive else { return }
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    guard isActive else { return }
                    lastOffset = offset
                }
        )
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
