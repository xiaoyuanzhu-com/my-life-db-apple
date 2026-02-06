//
//  LoginView.swift
//  MyLifeDB
//
//  Login screen shown when authentication is required.
//  Opens OAuth login in the default system browser.
//

import SwiftUI

struct LoginView: View {
    @AppStorage("apiBaseURL") private var apiBaseURL = "http://localhost:12345"
    @State private var showingServerSettings = false
    @State private var errorMessage: String?
    @State private var isRetrying = false

    private var authManager: AuthManager { .shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App icon and title
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)

                    Text("MyLifeDB")
                        .font(.largeTitle.bold())

                    Text("Personal Knowledge Management")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                    }
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Sign in button
                VStack(spacing: 16) {
                    Button {
                        errorMessage = nil
                        guard let url = URL(string: apiBaseURL) else {
                            errorMessage = "Invalid server URL"
                            return
                        }
                        OAuthHelper.openLoginInBrowser(baseURL: url)
                    } label: {
                        Label("Sign In", systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    // Retry without auth (for when server has auth_mode=none)
                    Button {
                        retryWithoutAuth()
                    } label: {
                        if isRetrying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Continue Without Login")
                                .font(.callout)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRetrying)
                }

                // Server info
                Button {
                    showingServerSettings = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .font(.caption)
                        Text(apiBaseURL)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 32)
            .sheet(isPresented: $showingServerSettings) {
                NavigationStack {
                    ServerSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingServerSettings = false
                                }
                            }
                        }
                }
            }
        }
    }

    private func retryWithoutAuth() {
        isRetrying = true
        errorMessage = nil
        Task {
            await authManager.checkAuth()
            isRetrying = false
            if !authManager.isAuthenticated {
                errorMessage = "Server requires authentication"
            }
        }
    }
}

#Preview {
    LoginView()
}
