#if LEGACY_NATIVE_VIEWS
//
//  TimestampView.swift
//  MyLifeDB
//
//  Displays relative timestamps for inbox items.
//  Shows "Just now", "5 min ago", "2 hours ago", "Yesterday", or date.
//

import SwiftUI

struct TimestampView: View {
    let dateString: String

    private var formattedTime: String {
        guard let date = parseDate(dateString) else {
            return dateString
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        // Less than 1 minute
        if interval < 60 {
            return "Just now"
        }

        // Less than 1 hour
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        }

        // Less than 24 hours
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        // Less than 2 days
        if interval < 172800 {
            return "Yesterday"
        }

        // Less than 7 days
        if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        }

        // Show date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Text(formattedTime)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func parseDate(_ string: String) -> Date? {
        // Try ISO8601 with fractional seconds
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        // Try ISO8601 without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: string)
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 8) {
        TimestampView(dateString: ISO8601DateFormatter().string(from: Date()))
        TimestampView(dateString: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)))
        TimestampView(dateString: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)))
        TimestampView(dateString: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-90000)))
        TimestampView(dateString: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-604800)))
    }
    .padding()
}

#endif // LEGACY_NATIVE_VIEWS
