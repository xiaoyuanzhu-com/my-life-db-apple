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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .frame(width: 200, height: 112)

            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
        }
        .padding(4)
    }
}
