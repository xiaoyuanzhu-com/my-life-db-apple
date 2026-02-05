//
//  GeneralSettingsView.swift
//  MyLifeDB
//
//  General app settings screen.
//  Currently a placeholder for future settings like appearance, notifications, etc.
//

import SwiftUI

struct GeneralSettingsView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No settings available yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("General settings will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
            .listRowBackground(Color.clear)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("General")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
