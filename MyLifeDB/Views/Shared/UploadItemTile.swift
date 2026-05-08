//
//  UploadItemTile.swift
//  MyLifeDB
//
//  Single tile in the share-extension upload progress sheet.
//
//  Layout:
//    - Square ~108pt rounded thumbnail (UIImage if decoded; SF Symbol fallback).
//    - Overlay layer driven by `ItemState`:
//        .pending      → dim mask + idle ProgressView.
//        .uploading(p) → dim mask + circular determinate ring.
//        .success      → no overlay (brief checkmark fade handled by parent).
//        .failed       → red mask + xmark.circle.fill.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

struct UploadItemTile: View {

    let item: UploadTracker.Item

    private let tileSize: CGFloat = 108
    private let cornerRadius: CGFloat = 12
    private let ringSize: CGFloat = 36
    private let ringStroke: CGFloat = 3

    var body: some View {
        ZStack {
            thumbnail
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            overlay
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .animation(.easeInOut(duration: 0.25), value: item.state)
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let image = item.thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: fallbackSymbol(for: item.mimeType))
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
        }
    }

    private func fallbackSymbol(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo.fill" }
        if mime.hasPrefix("video/") { return "film.fill" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "text/plain" { return "doc.text.fill" }
        return "doc.fill"
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        switch item.state {
        case .pending:
            ZStack {
                Color.black.opacity(0.4)
                ProgressView()
                    .tint(.white)
                    .controlSize(.regular)
            }
            .transition(.opacity)
        case .uploading(let progress):
            ZStack {
                Color.black.opacity(0.45)
                ProgressRing(progress: progress, size: ringSize, lineWidth: ringStroke)
            }
            .transition(.opacity)
        case .success:
            // Empty — parent handles the success transition + checkmark.
            Color.clear
        case .failed:
            ZStack {
                Color.red.opacity(0.45)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: ringSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - ProgressRing

private struct ProgressRing: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
        .frame(width: size, height: size)
    }
}
