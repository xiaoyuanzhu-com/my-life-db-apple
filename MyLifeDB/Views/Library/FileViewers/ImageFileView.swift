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
    @State private var zoomAnchor: UnitPoint = .center
    @State private var pendingSingleTapToken: UUID?
    @State private var lastTapAt: Date = .distantPast
    @State private var lastTapLocation: CGPoint = .zero

    private let zoomTarget: CGFloat = 1.5
    private let singleTapDelay: TimeInterval = 0.18
    private let doubleTapInterval: TimeInterval = 0.25
    private let doubleTapMaxDistance: CGFloat = 44

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
        .onDisappear {
            pendingSingleTapToken = nil
            lastTapAt = .distantPast
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
                .scaleEffect(scale, anchor: zoomAnchor)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .background(GeometryReader { geo in Color.clear.preference(key: ViewSizeKey.self, value: geo.size) })
                .onPreferenceChange(ViewSizeKey.self) { viewSize = $0 }
                .gesture(
                    SpatialTapGesture(count: 1)
                        .onEnded { value in
                            handleTap(at: value.location)
                        }
                )
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
                                let anchorDx = (0.5 - zoomAnchor.x) * viewSize.width * (scale - 1)
                                let anchorDy = (0.5 - zoomAnchor.y) * viewSize.height * (scale - 1)
                                zoomAnchor = .center
                                offset = CGSize(width: offset.width + anchorDx, height: offset.height + anchorDy)

                                withAnimation(.smooth(duration: 0.4)) {
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
                .scaleEffect(scale, anchor: zoomAnchor)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .background(GeometryReader { geo in Color.clear.preference(key: ViewSizeKey.self, value: geo.size) })
                .onPreferenceChange(ViewSizeKey.self) { viewSize = $0 }
                .gesture(
                    SpatialTapGesture(count: 1)
                        .onEnded { value in
                            handleTap(at: value.location)
                        }
                )
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
                                let anchorDx = (0.5 - zoomAnchor.x) * viewSize.width * (scale - 1)
                                let anchorDy = (0.5 - zoomAnchor.y) * viewSize.height * (scale - 1)
                                zoomAnchor = .center
                                offset = CGSize(width: offset.width + anchorDx, height: offset.height + anchorDy)

                                withAnimation(.smooth(duration: 0.4)) {
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

    private func handleTap(at location: CGPoint) {
        let now = Date()
        let distance = hypot(
            location.x - lastTapLocation.x,
            location.y - lastTapLocation.y
        )
        let isDoubleTap = now.timeIntervalSince(lastTapAt) <= doubleTapInterval && distance <= doubleTapMaxDistance

        lastTapAt = now
        lastTapLocation = location

        if isDoubleTap {
            pendingSingleTapToken = nil
            handleDoubleTap(at: location)
            lastTapAt = .distantPast
            return
        }

        let token = UUID()
        pendingSingleTapToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + singleTapDelay) {
            guard pendingSingleTapToken == token else { return }
            pendingSingleTapToken = nil
            onTap?()
        }
    }

    private func handleDoubleTap(at location: CGPoint) {
        if scale > 1.0 {
            // Zoom out: convert to center anchor (no visual change), then animate.
            let anchorDx = (0.5 - zoomAnchor.x) * viewSize.width * (scale - 1)
            let anchorDy = (0.5 - zoomAnchor.y) * viewSize.height * (scale - 1)
            zoomAnchor = .center
            offset = CGSize(width: offset.width + anchorDx, height: offset.height + anchorDy)
            lastOffset = offset

            withAnimation(.smooth(duration: 0.4)) {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        } else {
            // Zoom in: anchor at tap point — single unified zoom, no offset needed.
            zoomAnchor = UnitPoint(
                x: location.x / viewSize.width,
                y: location.y / viewSize.height
            )
            withAnimation(.smooth(duration: 0.4)) {
                scale = zoomTarget
            }
        }
    }
}

// MARK: - View Size Preference Key

private struct ViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Conditional Pan Gesture

/// Only attaches the DragGesture when active, so that pager horizontal
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
