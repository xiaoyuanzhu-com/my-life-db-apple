//
//  InboxView.swift
//  MyLifeDB
//
//  Displays inbox items from the backend API.
//  Items are files that need to be processed/organized.
//
//  API: GET /api/inbox
//

import SwiftUI

struct InboxView: View {
    var body: some View {
        NavigationStack {
            List {
                // TODO: Fetch and display inbox items from API
                Text("Inbox items will appear here")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

#Preview {
    InboxView()
}
