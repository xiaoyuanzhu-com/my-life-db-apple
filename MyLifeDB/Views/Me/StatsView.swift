//
//  StatsView.swift
//  MyLifeDB
//
//  App and data statistics screen.
//  Displays app version info.
//

import SwiftUI

struct StatsView: View {
    var body: some View {
        List {
            Section("App") {
                StatRow(label: "Version", value: appVersion)
                StatRow(label: "Build", value: buildNumber)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Stats")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}

struct StatRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
