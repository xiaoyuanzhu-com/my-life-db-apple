#if LEGACY_NATIVE_VIEWS
//
//  ClaudeView.swift
//  MyLifeDB
//
//  AI chat interface for interacting with Claude.
//  Users can ask questions about their data, get summaries, etc.
//

import SwiftUI

struct ClaudeView: View {
    @State private var messageText: String = ""

    var body: some View {
        NavigationStack {
            VStack {
                // Chat messages area
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // TODO: Display chat messages
                        Text("Start a conversation with Claude")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    }
                }

                Divider()

                // Message input area
                HStack(spacing: 12) {
                    TextField("Ask Claude...", text: $messageText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        // TODO: Send message to backend
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(messageText.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Claude")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

#Preview {
    ClaudeView()
}

#endif // LEGACY_NATIVE_VIEWS
