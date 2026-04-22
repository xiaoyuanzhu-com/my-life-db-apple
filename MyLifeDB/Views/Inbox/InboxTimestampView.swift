//
//  InboxTimestampView.swift
//  MyLifeDB
//
//  Displays relative timestamps for inbox items.
//  Uses RelativeDateTimeFormatter for locale-aware output.
//

import SwiftUI

struct InboxTimestampView: View {
    let epochMs: Int64

    var body: some View {
        Text(formattedTime)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .named  // gives "yesterday", "today" etc.
        return f
    }()

    private var formattedTime: String {
        let date = epochMs.asDate
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return String(localized: "Just now")
        }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
