//
//  ClaudeSessionDetailView.swift
//  MyLifeDB
//
//  WebView wrapper for viewing a single Claude session.
//  Navigates the shared Claude TabWebViewModel to /claude/{sessionId}.
//

import SwiftUI

struct ClaudeSessionDetailView: View {

    let session: ClaudeSession
    let claudeVM: TabWebViewModel

    var body: some View {
        ZStack {
            WebViewContainer(viewModel: claudeVM)
                #if !os(macOS)
                .ignoresSafeArea(edges: .bottom)
                #endif

            if !claudeVM.isLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.platformBackground)
            }
        }
        .navigationTitle(session.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            claudeVM.navigateTo(path: "/claude/\(session.id)")
        }
        .onDisappear {
            // Reset WebView to session list when navigating back
            claudeVM.navigateTo(path: "/claude")
        }
    }
}
