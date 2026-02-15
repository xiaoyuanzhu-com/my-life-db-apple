//
//  InboxVideoCard.swift
//  MyLifeDB
//
//  Card component for displaying video items.
//

import SwiftUI

struct InboxVideoCard: View {
    let item: InboxItem

    var body: some View {
        ZStack {
            Color.black
                .frame(width: 200, height: 112)

            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
