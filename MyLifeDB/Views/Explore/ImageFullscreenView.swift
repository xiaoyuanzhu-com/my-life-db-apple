//
//  ImageFullscreenView.swift
//  MyLifeDB
//
//  Fullscreen image viewer with swipe-to-navigate between images.
//

import SwiftUI

struct ImageFullscreenView: View {

    let images: [String]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @GestureState private var dragOffset: CGFloat = 0

    init(images: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.images = images
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Image carousel
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(images.indices, id: \.self) { index in
                        AuthenticatedImage(path: images[index])
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }
                .offset(x: -CGFloat(currentIndex) * geo.size.width + dragOffset)
                .animation(.easeOut(duration: 0.25), value: currentIndex)
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let threshold: CGFloat = geo.size.width * 0.25
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            if value.translation.width < -threshold || velocity < -200 {
                                currentIndex = min(currentIndex + 1, images.count - 1)
                            } else if value.translation.width > threshold || velocity > 200 {
                                currentIndex = max(currentIndex - 1, 0)
                            }
                        }
                )
            }

            // Overlay controls
            VStack {
                HStack {
                    // Counter
                    if images.count > 1 {
                        Text("\(currentIndex + 1)/\(images.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()

                Spacer()

                // Dot indicators
                if images.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .statusBar(hidden: true)
    }
}
