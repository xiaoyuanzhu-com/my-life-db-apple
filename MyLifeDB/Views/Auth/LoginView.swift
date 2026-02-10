//
//  LoginView.swift
//  MyLifeDB
//
//  Native init page shown before login.
//  Presents ASWebAuthenticationSession for OAuth sign-in.
//

import SwiftUI

struct LoginView: View {
    @AppStorage("apiBaseURL") private var apiBaseURL = "https://my.xiaoyuanzhu.com"
    @State private var showingOAuth = false
    @State private var showingServerSettings = false
    @State private var errorMessage: String?
    @State private var appeared = false

    private var authManager: AuthManager { .shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // MARK: - Branding
                VStack(spacing: 16) {
                    appIcon
                        .frame(width: 80, height: 80)
                        .clipShape(.rect(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                    VStack(spacing: 6) {
                        Text("MyLifeDB")
                            .font(.largeTitle.bold())

                        Text("Personal Knowledge Management")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // MARK: - Actions
                VStack(spacing: 20) {
                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.callout)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        errorMessage = nil
                        showingOAuth = true
                    } label: {
                        Label("Sign In", systemImage: "person.badge.key")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
                    .frame(height: 40)

                // MARK: - Server footer
                Button {
                    showingServerSettings = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "server.rack")
                            .font(.caption2)
                        Text(apiBaseURL)
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 400)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.5), value: appeared)
            .onAppear { appeared = true }
            .sheet(isPresented: $showingOAuth) {
                if let url = URL(string: apiBaseURL) {
                    OAuthWebView(
                        baseURL: url,
                        onCompletion: { accessToken, refreshToken in
                            showingOAuth = false
                            authManager.handleOAuthCompletion(
                                accessToken: accessToken,
                                refreshToken: refreshToken
                            )
                        },
                        onError: { message in
                            showingOAuth = false
                            errorMessage = message
                        },
                        onCancel: {
                            showingOAuth = false
                        }
                    )
                }
            }
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

    // MARK: - App Icon

    @ViewBuilder
    private var appIcon: some View {
        if let uiImage = imageFromAsset("AppLogo") {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.tint.opacity(0.1))
        }
    }

    private func imageFromAsset(_ name: String) -> PlatformImage? {
        #if os(macOS)
        return NSImage(named: name)
        #else
        return UIImage(named: name)
        #endif
    }
}

#if os(macOS)
private typealias PlatformImage = NSImage
extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}
#else
private typealias PlatformImage = UIImage
#endif

#Preview {
    LoginView()
}
