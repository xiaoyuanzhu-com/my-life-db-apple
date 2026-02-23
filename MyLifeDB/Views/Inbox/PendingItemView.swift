//
//  PendingItemView.swift
//  MyLifeDB
//
//  Displays a pending inbox item that is uploading or failed.
//  Shows upload status, retry countdown, and cancel option.
//

import SwiftUI

// MARK: - Pending Item Model

struct PendingInboxItem: Identifiable {
    let id: String
    let text: String
    var files: [InboxFileAttachment]
    var status: PendingStatus
    var error: String?
    var retryAt: Date?
    var retryCount: Int = 0

    enum PendingStatus {
        case uploading
        case failed
        case queued
    }
}

// MARK: - Pending Item View

struct PendingItemView: View {
    let item: PendingInboxItem
    let onCancel: () -> Void
    let onRetry: () -> Void

    @State private var showSpinner = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Status row
            HStack(spacing: 6) {
                statusIndicator
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)

                if item.status == .uploading {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if item.status == .failed {
                    Button {
                        onRetry()
                    } label: {
                        Text("Retry")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Preview card
            pendingCard
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch item.status {
        case .uploading:
            if showSpinner {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "arrow.up.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        case .queued:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch item.status {
        case .uploading: return "Sending..."
        case .failed: return item.error ?? "Failed"
        case .queued:
            if let retryAt = item.retryAt {
                let seconds = max(0, Int(retryAt.timeIntervalSinceNow))
                return "retry in \(seconds)s"
            }
            return "Queued"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .uploading: return .secondary
        case .failed: return .red
        case .queued: return .secondary
        }
    }

    private var pendingCard: some View {
        Group {
            if !item.text.isEmpty {
                Text(item.text)
                    .font(.body)
                    .lineLimit(5)
                    .padding(12)
                    .frame(maxWidth: 320, alignment: .leading)
            } else if let firstFile = item.files.first {
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(firstFile.filename)
                        .font(.subheadline)
                        .lineLimit(1)
                    if item.files.count > 1 {
                        Text("+\(item.files.count - 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .opacity(item.status == .failed ? 0.6 : 0.8)
        .task {
            // Show spinner after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            if item.status == .uploading {
                showSpinner = true
            }
        }
    }
}
