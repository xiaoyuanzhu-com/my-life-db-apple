//
//  InboxImageCard.swift
//  MyLifeDB
//
//  Card component for displaying images.
//  Uses AuthenticatedImage for loading with auth headers.
//  Simple: just the image, matching web's image-card.tsx.
//

import SwiftUI

struct InboxImageCard: View {
    let item: InboxItem

    private var screenHeight: CGFloat {
        #if os(iOS) || os(visionOS)
        UIScreen.main.bounds.height
        #elseif os(macOS)
        NSScreen.main?.frame.height ?? 800
        #endif
    }

    var body: some View {
        AuthenticatedImage(path: item.path)
            .frame(maxWidth: 320, maxHeight: screenHeight * 0.2, alignment: .trailing)
    }
}
