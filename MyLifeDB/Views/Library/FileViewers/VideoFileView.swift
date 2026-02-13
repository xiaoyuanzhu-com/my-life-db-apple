//
//  VideoFileView.swift
//  MyLifeDB
//
//  Native video player using AVKit.
//  Uses AVURLAsset with HTTP header injection for authentication.
//

import SwiftUI
import AVKit

struct VideoFileView: View {

    let path: String

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("Loading video...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

        // Inject auth header via AVURLAsset options
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
