//
//  OAuthWebView.swift
//  MyLifeDB
//
//  WKWebView wrapper for OAuth login flow.
//  Loads the backend's /api/oauth/authorize, monitors for completion,
//  and extracts auth cookies from the web view.
//

import SwiftUI
import WebKit

struct OAuthWebView: View {
    let baseURL: URL
    let onCompletion: (String, String?) -> Void // (accessToken, refreshToken?)
    let onError: (String) -> Void
    let onCancel: () -> Void

    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WebViewRepresentable(
                    url: baseURL.appendingPathComponent("api/oauth/authorize"),
                    baseURL: baseURL,
                    isLoading: $isLoading,
                    onCompletion: onCompletion,
                    onError: { message in
                        errorMessage = message
                        onError(message)
                    }
                )

                if isLoading {
                    ProgressView("Loading...")
                }

                if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Sign In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Platform WebView Representable

#if os(iOS)
private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    let baseURL: URL
    @Binding var isLoading: Bool
    let onCompletion: (String, String?) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, isLoading: $isLoading, onCompletion: onCompletion, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#elseif os(macOS)
private struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let baseURL: URL
    @Binding var isLoading: Bool
    let onCompletion: (String, String?) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, isLoading: $isLoading, onCompletion: onCompletion, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif

// MARK: - Coordinator

private class Coordinator: NSObject, WKNavigationDelegate {
    let baseURL: URL
    @Binding var isLoading: Bool
    let onCompletion: (String, String?) -> Void
    let onError: (String) -> Void
    private var hasCompleted = false

    init(
        baseURL: URL,
        isLoading: Binding<Bool>,
        onCompletion: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.baseURL = baseURL
        self._isLoading = isLoading
        self.onCompletion = onCompletion
        self.onError = onError
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        // Check if redirected back to base URL root (OAuth complete)
        if isBaseURLRoot(url) && !hasCompleted {
            hasCompleted = true

            // Check for error params in URL
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
                await MainActor.run {
                    onError("Login failed: \(errorParam)")
                }
                return .cancel
            }

            // Extract cookies from the web view
            await extractCookies(from: webView)
            return .cancel
        }

        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            isLoading = false
        }

        // Also check current URL after page finishes loading
        guard let url = webView.url, !hasCompleted else { return }
        if isBaseURLRoot(url) {
            hasCompleted = true

            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
                Task { @MainActor in
                    onError("Login failed: \(errorParam)")
                }
                return
            }

            Task {
                await extractCookies(from: webView)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
            onError("Connection failed: \(error.localizedDescription)")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            isLoading = false
            onError("Could not connect to server: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func isBaseURLRoot(_ url: URL) -> Bool {
        // Match the base URL root path (OAuth callback redirects to "/")
        guard let baseHost = baseURL.host, let urlHost = url.host else { return false }
        return baseHost == urlHost
            && baseURL.port == url.port
            && (url.path == "/" || url.path.isEmpty)
    }

    private func extractCookies(from webView: WKWebView) async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()

        var accessToken: String?
        var refreshToken: String?

        for cookie in cookies {
            if cookie.name == "access_token" {
                accessToken = cookie.value
            } else if cookie.name == "refresh_token" {
                refreshToken = cookie.value
            }
        }

        await MainActor.run {
            if let accessToken = accessToken {
                onCompletion(accessToken, refreshToken)
            } else {
                onError("Login completed but no auth token received")
            }
        }
    }
}
