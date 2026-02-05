//
//  LibraryView.swift
//  MyLifeDB
//
//  Displays the organized file tree from the backend.
//  Users can browse folders and view files.
//
//  API: GET /api/library/tree
//

import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            List {
                // TODO: Fetch and display library tree from API
                Text("Library folders will appear here")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

#Preview {
    LibraryView()
}
