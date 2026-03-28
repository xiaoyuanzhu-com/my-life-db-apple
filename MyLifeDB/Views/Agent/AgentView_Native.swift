#if LEGACY_NATIVE_VIEWS
//
//  AgentView.swift
//  MyLifeDB
//
//  AI chat interface for interacting with agents.
//  Users can ask questions about their data, get summaries, etc.
//

import SwiftUI

struct AgentView: View {
    @State private var messageText: String = ""

    var body: some View {
        NavigationStack {
            VStack {
                // Chat messages area
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // TODO: Display chat messages
                        Text("Start a conversation")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    }
                }

                Divider()

                // Message input area
                HStack(spacing: 12) {
                    TextField("Ask a question...", text: $messageText)
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
            .navigationTitle("Agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

#Preview {
    AgentView()
}

#endif // LEGACY_NATIVE_VIEWS
