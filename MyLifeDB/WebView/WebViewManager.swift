//
//  WebViewManager.swift
//  MyLifeDB
//
//  Singleton managing a single persistent WKWebView instance.
//  The WebView is shared across all tabs — tab switches navigate the React Router
//  via JavaScript (no page reload), keeping the SPA state intact.
//
//  Architecture note: @Observable cannot be applied to NSObject subclasses.
//  So we split into:
//  - WebViewManager (@Observable) — state and API surface
//  - WebViewNavigationDelegate (NSObject) — WKNavigationDelegate conformance
//

import WebKit
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - WebViewManager

@Observable
final class WebViewManager {

    // MARK: - Singleton

    static let shared = WebViewManager()

    // MARK: - Observable State

    /// The shared WKWebView instance. Nil until `setup()` is called.
    private(set) var webView: WKWebView?

    /// Whether the initial page load has completed.
    private(set) var isLoaded = false

    /// The current WebView route path (best-effort tracking).
    private(set) var currentPath: String = "/"

    /// Error from the last navigation attempt, if any.
    private(set) var loadError: Error?

    // MARK: - Non-observable State

    /// The base URL of the backend (e.g., http://localhost:12345).
    private var baseURL: URL?

    /// The navigation delegate (separate NSObject to avoid @Observable + NSObject conflict).
    private var navigationDelegate: WebViewNavigationDelegate?

    // MARK: - Bridge

    let bridgeHandler = NativeBridgeHandler()

    // MARK: - Init

    private init() {}

    // MARK: - Setup

    /// Create the WebView, inject auth cookies, and load the base URL.
    /// Call this after authentication is confirmed.
    @MainActor
    func setup(baseURL: URL) async {
        // Avoid double-setup
        guard self.webView == nil else {
            // If base URL changed, reload
            if self.baseURL != baseURL {
                self.baseURL = baseURL
                await teardownAndReload(baseURL: baseURL)
            }
            return
        }

        self.baseURL = baseURL

        let config = WebViewConfiguration.create(bridgeHandler: bridgeHandler)
        let webView = WKWebView(frame: .zero, configuration: config)

        // Create the delegate and wire it up
        let delegate = WebViewNavigationDelegate(manager: self)
        self.navigationDelegate = delegate
        webView.navigationDelegate = delegate

        #if os(iOS)
        // Match system scroll behavior and safe areas
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Transparent background during loading to match native theme
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif

        self.webView = webView

        // Inject auth cookies before loading
        await injectAuthCookies(into: webView, for: baseURL)

        // Load the SPA
        let request = URLRequest(url: baseURL)
        webView.load(request)
    }

    // MARK: - Navigation

    /// Navigate the React Router to a given path (no page reload).
    @MainActor
    func navigateTo(path: String) {
        currentPath = path

        guard let webView = webView, isLoaded else {
            // Path stored; will be applied when load completes
            return
        }

        let js = "window.__nativeBridge?.navigateTo('\(path.escapedForJS)')"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[WebViewManager] navigateTo error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Theme Sync

    /// Push the current system appearance to the WebView.
    @MainActor
    func syncTheme() {
        let isDark: Bool
        #if os(iOS)
        isDark = UITraitCollection.current.userInterfaceStyle == .dark
        #elseif os(macOS)
        isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
        isDark = false
        #endif

        setTheme(isDark: isDark)
    }

    /// Explicitly set the WebView theme.
    @MainActor
    func setTheme(isDark: Bool) {
        let theme = isDark ? "dark" : "light"
        let js = "window.__nativeBridge?.setTheme('\(theme)')"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Auth Cookie Management

    /// Inject the current auth tokens as cookies into the WebView's cookie store.
    @MainActor
    func injectAuthCookies(into webView: WKWebView, for baseURL: URL) async {
        guard let host = baseURL.host else { return }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        // Inject access token
        if let accessToken = AuthManager.shared.accessToken {
            if let cookie = HTTPCookie(properties: [
                .name: "access_token",
                .value: accessToken,
                .domain: host,
                .path: "/",
                .secure: baseURL.scheme == "https" ? "TRUE" : "FALSE",
            ]) {
                await cookieStore.setCookie(cookie)
            }
        }
    }

    /// Update auth cookies after a token refresh.
    @MainActor
    func updateAuthCookies() async {
        guard let webView = webView, let baseURL = baseURL else { return }
        await injectAuthCookies(into: webView, for: baseURL)
    }

    // MARK: - Reload

    /// Reload the current page.
    @MainActor
    func reload() {
        loadError = nil
        webView?.reload()
    }

    /// Tell the web frontend to refresh its data (without a full page reload).
    @MainActor
    func refreshData() {
        let js = "window.__nativeBridge?.refresh()"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Teardown

    /// Tear down the current WebView and set up a new one with a different base URL.
    @MainActor
    func teardownAndReload(baseURL: URL) async {
        isLoaded = false
        loadError = nil

        // Remove the old WebView's message handler to avoid leaks
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "native")
        webView?.navigationDelegate = nil
        navigationDelegate = nil
        webView = nil

        self.baseURL = baseURL
        await setup(baseURL: baseURL)
    }

    // MARK: - Evaluate JavaScript

    /// Convenience for running arbitrary JS in the WebView.
    @MainActor
    func evaluateJS(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Delegate Callbacks (called by WebViewNavigationDelegate)

    @MainActor
    func handleDidFinishNavigation() {
        isLoaded = true
        loadError = nil

        // Sync theme on first load
        syncTheme()

        // Signal the web frontend to re-check auth.
        // WKWebView cookies set via WKHTTPCookieStore may not be available
        // during the initial React mount, so we re-trigger after page load.
        let js = "window.__nativeBridge?.recheckAuth()"
        webView?.evaluateJavaScript(js, completionHandler: nil)

        // Navigate to the desired path if it was set before load completed
        if currentPath != "/" {
            navigateTo(path: currentPath)
        }
    }

    @MainActor
    func handleNavigationFailed(error: Error) {
        loadError = error
        print("[WebViewManager] Navigation failed: \(error.localizedDescription)")
    }

    @MainActor
    func handleProvisionalNavigationFailed(error: Error) {
        isLoaded = false
        loadError = error
        print("[WebViewManager] Provisional navigation failed: \(error.localizedDescription)")
    }

    @MainActor
    func handleProcessTerminated(webView: WKWebView) {
        print("[WebViewManager] WebView process terminated, reloading...")
        isLoaded = false
        webView.reload()
    }
}

// MARK: - WebViewNavigationDelegate

/// Separate NSObject subclass for WKNavigationDelegate conformance.
/// Delegates all callbacks to the @Observable WebViewManager.
private class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {

    weak var manager: WebViewManager?

    init(manager: WebViewManager) {
        self.manager = manager
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            manager?.handleDidFinishNavigation()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            manager?.handleNavigationFailed(error: error)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            manager?.handleProvisionalNavigationFailed(error: error)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            manager?.handleProcessTerminated(webView: webView)
        }
    }
}

// MARK: - String Extension for JS Escaping

private extension String {
    /// Escape a string for safe embedding in a JavaScript single-quoted string literal.
    var escapedForJS: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
