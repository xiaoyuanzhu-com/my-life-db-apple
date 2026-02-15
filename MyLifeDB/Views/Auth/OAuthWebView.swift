//
//  OAuthWebView.swift
//  MyLifeDB
//
//  ASWebAuthenticationSession-based OAuth login flow.
//  Shares cookies with Safari so users already logged into the IdP
//  get authenticated instantly without re-entering credentials.
//

import AuthenticationServices
import SwiftUI

struct OAuthWebView: View {
    let baseURL: URL
    let onCompletion: (String, String?) -> Void // (accessToken, refreshToken?)
    let onError: (String) -> Void
    let onCancel: () -> Void

    @State private var sessionHolder: SessionHolder?

    var body: some View {
        ProgressView("Signing in...")
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await startOAuthFlow()
            }
            .onDisappear {
                sessionHolder = nil
            }
    }

    @MainActor
    private func startOAuthFlow() async {
        let callbackScheme = "mylifedb"
        let nativeRedirect = "\(callbackScheme)://oauth/callback"
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/oauth/authorize"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "native_redirect", value: nativeRedirect)
        ]

        guard let authorizeURL = components?.url else {
            onError("Invalid server URL")
            return
        }

        do {
            let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in

                let session = ASWebAuthenticationSession(
                    url: authorizeURL,
                    callbackURLScheme: callbackScheme
                ) { callbackURL, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let callbackURL = callbackURL else {
                        continuation.resume(throwing: OAuthError.noCallbackURL)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }

                // Share cookies with Safari — if user is already logged into the IdP,
                // the flow completes instantly without showing a login form
                session.prefersEphemeralWebBrowserSession = false

                let holder = SessionHolder(session: session)

                #if os(iOS)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.keyWindow {
                    holder.contextProvider = iOSContextProvider(anchor: window)
                    session.presentationContextProvider = holder.contextProvider
                }
                #elseif os(macOS)
                if let window = NSApplication.shared.keyWindow {
                    holder.contextProvider = macOSContextProvider(anchor: window)
                    session.presentationContextProvider = holder.contextProvider
                }
                #endif

                self.sessionHolder = holder
                session.start()
            }

            // Parse tokens from callback URL
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                onError("Invalid callback URL")
                return
            }

            let queryItems = components.queryItems ?? []
            guard let accessToken = queryItems.first(where: { $0.name == "access_token" })?.value else {
                if let error = queryItems.first(where: { $0.name == "error" })?.value {
                    onError("Login failed: \(error)")
                } else {
                    onError("No access token received")
                }
                return
            }

            let refreshToken = queryItems.first(where: { $0.name == "refresh_token" })?.value
            onCompletion(accessToken, refreshToken)

        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            onCancel()
        } catch {
            onError("Login failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Session Holder (prevents ARC deallocation)

private class SessionHolder {
    let session: ASWebAuthenticationSession
    #if os(iOS)
    var contextProvider: iOSContextProvider?
    #elseif os(macOS)
    var contextProvider: macOSContextProvider?
    #endif

    init(session: ASWebAuthenticationSession) {
        self.session = session
    }
}

// MARK: - Errors

private enum OAuthError: LocalizedError {
    case noCallbackURL

    var errorDescription: String? {
        switch self {
        case .noCallbackURL: return "No callback URL received"
        }
    }
}

// MARK: - Presentation Context Providers

#if os(iOS)
private class iOSContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: UIWindow

    init(anchor: UIWindow) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#elseif os(macOS)
private class macOSContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: NSWindow

    init(anchor: NSWindow) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#endif
