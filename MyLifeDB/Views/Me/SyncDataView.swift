//
//  SyncDataView.swift
//  MyLifeDB
//
//  Full-page view for "Sync All History" that shows a calendar grid
//  with per-day sync progress across the entire HealthKit date range.
//

import SwiftUI

struct SyncDataView: View {
    private var syncManager = SyncManager.shared
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let progress = syncManager.fullSyncProgress {
                calendarContent(progress)
            } else {
                emptyView
            }
        }
        .navigationTitle("Health Data Sync")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if syncManager.state == .idle && syncManager.hasResumableFullSync {
                    Menu {
                        Button(role: .destructive) {
                            syncManager.clearFullSyncProgress()
                            isLoading = true
                            Task {
                                await syncManager.prepareFullSync()
                                isLoading = false
                            }
                        } label: {
                            Label("Reset Progress", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            if syncManager.fullSyncProgress == nil {
                await syncManager.prepareFullSync()
            }
            isLoading = false
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Discovering data range...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        ContentUnavailableView(
            "No Health Data Sources",
            systemImage: "heart.slash",
            description: Text("Enable health data sources in Data Collect to sync history.")
        )
    }

    // MARK: - Calendar Content

    @ViewBuilder
    private func calendarContent(_ progress: FullSyncProgress) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                headerSection(progress)

                // Calendar grid
                ForEach(progress.years, id: \.self) { year in
                    YearSection(
                        year: year,
                        months: progress.months(for: year),
                        yearStatus: progress.yearStatus(year)
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ progress: FullSyncProgress) -> some View {
        VStack(spacing: 12) {
            // Summary line
            if let firstYear = progress.years.first, let lastYear = progress.years.last {
                let typeCount = enabledTypeCount
                Text("\(typeCount) type\(typeCount == 1 ? "" : "s") \u{00B7} \(String(firstYear))\u{2013}\(String(lastYear))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 16) {
                actionButton

                if hasErrors(progress) {
                    Button {
                        retryFailed()
                    } label: {
                        Text("Retry Failed")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch syncManager.state {
        case .syncingAll:
            Button {
                syncManager.cancelSync()
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)

        case .idle:
            if syncManager.hasResumableFullSync {
                Button {
                    syncManager.syncAll()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    syncManager.syncAll()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
            }

        case .syncing:
            Button {
                // Already syncing (regular sync), disabled
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
    }

    // MARK: - Helpers

    /// Number of enabled health data source types.
    private var enabledTypeCount: Int {
        // Count AppStorage keys that match dataCollect.* pattern and are true
        let allSourceIDs = dataCategories.flatMap(\.sources).map(\.id)
        return allSourceIDs.filter { UserDefaults.standard.bool(forKey: "dataCollect.\($0)") }.count
    }

    /// Whether any day in the progress has an error status.
    private func hasErrors(_ progress: FullSyncProgress) -> Bool {
        progress.months.contains { month in
            month.dayStatuses.values.contains { status in
                if case .error = status { return true }
                return false
            }
        }
    }

    /// Reset error days back to pending, then start sync.
    private func retryFailed() {
        guard var progress = syncManager.fullSyncProgress else { return }

        for i in progress.months.indices {
            let keysToReset = progress.months[i].dayStatuses.filter { _, status in
                if case .error = status { return true }
                return false
            }.map(\.key)

            for day in keysToReset {
                progress.months[i].dayStatuses[day] = .pending
            }
        }

        syncManager.fullSyncProgress = progress
        syncManager.syncAll()
    }
}

#Preview {
    NavigationStack {
        SyncDataView()
    }
}
