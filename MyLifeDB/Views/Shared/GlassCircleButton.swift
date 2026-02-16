//
//  GlassCircleButton.swift
//  MyLifeDB
//
//  Reusable circular glass-effect button for overlay controls
//  (e.g. dismiss, share). Ensures consistent sizing and style
//  across the app.
//

import SwiftUI

struct GlassCircleButton: View {

    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .padding(10)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}
