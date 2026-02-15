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
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return scene?.screen.bounds.height ?? 800
        #elseif os(macOS)
        NSScreen.main?.frame.height ?? 800
        #endif
    }

    var body: some View {
        AuthenticatedImage(path: item.path)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxHeight: screenHeight * 0.2, alignment: .trailing)
    }
}
