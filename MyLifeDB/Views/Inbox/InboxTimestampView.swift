//
//  InboxTimestampView.swift
//  MyLifeDB
//
//  Displays relative timestamps for inbox items.
//  Shows "Just now", "5 min ago", "2 hours ago", "Yesterday", or date.
//

import SwiftUI

struct InboxTimestampView: View {
    let dateString: String

    var body: some View {
        Text(formattedTime)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var formattedTime: String {
        guard let date = parseDate(dateString) else {
            return dateString
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        }
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if interval < 172800 {
            return "Yesterday"
        }
        if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func parseDate(_ string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: string)
    }
}
