//
//  StatsView.swift
//  MyLifeDB
//
//  App and data statistics screen.
//  Fetches counts from API endpoints and displays app version info.
//

import SwiftUI

struct StatsView: View {
    @State private var inboxCount: Int?
    @State private var isLoadingInbox = false
    @State private var inboxError: Error?

    var body: some View {
        List {
            Section("App") {
                StatRow(label: "Version", value: appVersion)
                StatRow(label: "Build", value: buildNumber)
            }

            Section("Data") {
                HStack {
                    Text("Inbox Items")
                    Spacer()
                    if isLoadingInbox {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let count = inboxCount {
                        Text("\(count)")
                            .foregroundColor(.secondary)
                    } else if inboxError != nil {
                        Text("—")
                            .foregroundColor(.secondary)
                    } else {
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle("Stats")
        .task {
            await loadStats()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private func loadStats() async {
        isLoadingInbox = true
        inboxError = nil

        do {
            let response = try await APIClient.shared.inbox.list()
            await MainActor.run {
                inboxCount = response.items.count
                isLoadingInbox = false
            }
        } catch {
            await MainActor.run {
                inboxError = error
                isLoadingInbox = false
            }
        }
    }
}

struct StatRow: View {
    let label: String
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
