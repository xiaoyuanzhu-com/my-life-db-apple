//
//  InboxTimestampView.swift
//  MyLifeDB
//
//  Displays relative timestamps for inbox items.
//  Shows "Just now", "5 min ago", "2 hours ago", "Yesterday", or date.
//

import SwiftUI

struct InboxTimestampView: View {
    let epochMs: Int64

    var body: some View {
        Text(formattedTime)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var formattedTime: String {
        let date = epochMs.asDate

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
}
