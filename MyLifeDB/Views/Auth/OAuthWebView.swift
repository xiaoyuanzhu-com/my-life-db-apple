//
//  OAuthWebView.swift
//  MyLifeDB
//
//  ASWebAuthenticationSession-based OAuth login flow.
//  Opens the backend's /api/oauth/authorize with a native redirect param,
//  and receives tokens via the mylifedb:// custom URL scheme callback.
//

import AuthenticationServices
import SwiftUI

struct OAuthWebView: View {
    let baseURL: URL
    let onCompletion: (String, String?) -> Void // (accessToken, refreshToken?)
    let onError: (String) -> Void
    let onCancel: () -> Void

    @State private var isLoading = false
    @State private var sessionHolder: SessionHolder?

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView("Signing in...")
                    .padding()
            }
        }
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
        isLoading = true

        // Build authorize URL with native redirect parameter
        let callbackScheme = "mylifedb"
        let nativeRedirect = "\(callbackScheme)://oauth/callback"
        var components = URLComponents(url: baseURL.appendingPathComponent("api/oauth/authorize"), resolvingAgainstBaseURL: true)
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

                session.prefersEphemeralWebBrowserSession = true

                // Hold a strong reference so the session isn't deallocated
                let holder = SessionHolder(session: session)

                #if os(iOS)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    holder.contextProvider = PresentationContextProvider(anchor: window)
                    session.presentationContextProvider = holder.contextProvider
                }
                #elseif os(macOS)
                if let window = NSApplication.shared.keyWindow {
                    holder.contextProvider = PresentationContextProvider(anchor: window)
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
    var contextProvider: PresentationContextProvider?

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

// MARK: - Presentation Context Provider

#if os(iOS)
private class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: UIWindow

    init(anchor: UIWindow) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#elseif os(macOS)
private class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: NSWindow

    init(anchor: NSWindow) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#endif
