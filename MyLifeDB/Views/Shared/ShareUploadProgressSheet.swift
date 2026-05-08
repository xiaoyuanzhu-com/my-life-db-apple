//
//  ShareUploadProgressSheet.swift
//  MyLifeDB
//
//  Sheet shown when the user taps "Go to MyLifeDB" from the Share
//  Extension. Renders all files as a tile grid; one uploads at a
//  time. Auto-dismisses ~1.5s after every tile reaches a terminal
//  state (success/failure). The user can swipe down at any time —
//  uploads continue in the background.
//

import SwiftUI

struct ShareUploadProgressSheet: View {

    let share: UploadTracker.ShareUpload
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 132), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(share.items) { item in
                        UploadItemTile(item: item)
                    }
                }
                .padding(16)
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Text(share.allFinished ? "Done" : "Hide")
                    }
                }
                #else
                ToolbarItem {
                    Button(action: onDismiss) {
                        Text(share.allFinished ? "Done" : "Hide")
                    }
                }
                #endif
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .interactiveDismissDisabled(false)
    }

    private var navigationTitle: String {
        if share.allFinished {
            let failed = share.items.filter { if case .failed = $0.state { return true } else { return false } }
            if failed.isEmpty {
                return share.items.count == 1 ? "Sent" : "All Sent"
            } else {
                return "\(failed.count) Failed"
            }
        }
        let done = share.items.filter { if case .success = $0.state { return true } else { return false } }.count
        return "Sending \(done + 1) of \(share.items.count)"
    }
}
