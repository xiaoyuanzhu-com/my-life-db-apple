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

    var body: some View {
        AuthenticatedImage(path: item.path)
            .frame(maxWidth: 320, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(4)
    }
}
