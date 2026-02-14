//
//  ShareView.swift
//  MyLifeDBShareExtension
//
//  SwiftUI compose view for the Share Extension.
//  Displays a compose sheet where users can add a note
//  and preview what they're sharing before sending to Inbox.
//

import SwiftUI

struct ShareView: View {
    @Bindable var viewModel: ShareViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    loadingView

                case .notAuthenticated:
                    notAuthenticatedView

                case .ready:
                    composeView

                case .uploading:
                    uploadingView

                case .success:
                    successView

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Send to Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.state != .uploading {
                        Button("Cancel") { onDismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.state == .ready {
                        Button("Send") {
                            Task { await viewModel.upload() }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compose

    private var composeView: some View {
        Form {
            Section {
                TextField("Add a note...", text: $viewModel.userNote, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Note")
            }

            Section {
                Text(viewModel.contentPreview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(15)
            } header: {
                Text("Content")
            }
        }
    }

    // MARK: - Uploading

    private var uploadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Sending to Inbox...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Sent to Inbox")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Auto-dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        }
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Not Signed In")
                .font(.headline)
            Text("Please open MyLifeDB and sign in first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Send")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.bordered)
                Button("Retry") {
                    Task { await viewModel.upload() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
