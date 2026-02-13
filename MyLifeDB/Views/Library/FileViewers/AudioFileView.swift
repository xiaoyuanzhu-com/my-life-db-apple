//
//  AudioFileView.swift
//  MyLifeDB
//
//  Native audio player using AVKit.
//  Shows a centered icon with the filename and built-in playback controls.
//

import SwiftUI
import AVKit

struct AudioFileView: View {

    let path: String
    let fileName: String

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text(fileName)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // VideoPlayer provides built-in transport controls for audio too
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
            } else {
                ProgressView()
            }

            Spacer()
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        let url = APIClient.shared.library.rawFileURL(path: path)

        var headers: [String: String] = [:]
        if let token = AuthManager.shared.accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
    }
}
