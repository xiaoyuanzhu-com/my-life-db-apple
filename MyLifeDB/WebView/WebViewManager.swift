//
//  TabWebViewModel.swift
//  MyLifeDB
//
//  Per-tab WebView model. Each web tab (Inbox, Claude) creates its own
//  instance, which owns an independent WebPage loaded at a fixed route.
//
//  Uses the SwiftUI-native WebView/WebPage API (iOS 26+).
//

import WebKit
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Notification for server URL changes

extension Notification.Name {
    static let webViewShouldReload = Notification.Name("webViewShouldReload")
}

// MARK: - TabWebViewModel

@Observable
final class TabWebViewModel {

    // MARK: - Configuration

    /// The route this WebView is pinned to (e.g. "/", "/claude").
    let route: String

    // MARK: - Observable State

    /// The WebPage instance that backs the SwiftUI WebView.
    private(set) var webPage: WebPage

    /// Whether the initial page load has completed.
    private(set) var isLoaded = false

    /// Error from the last navigation attempt, if any.
    private(set) var loadError: Error?

    // MARK: - Non-observable State

    /// The base URL of the backend (e.g., http://localhost:12345).
    private var baseURL: URL?

    /// Whether the bridge polyfill has been injected for the current page load.
    private var bridgeInjected = false

    // MARK: - Bridge

    let bridgeHandler = NativeBridgeHandler()

    // MARK: - Init

    init(route: String) {
        self.route = route
        let config = WebViewConfiguration.create(bridgeHandler: bridgeHandler)
        self.webPage = WebPage(configuration: config)
    }

    // MARK: - Setup

    /// Inject auth cookies and load the base URL + route.
    /// Call this after authentication is confirmed.
    @MainActor
    func setup(baseURL: URL) async {
        // Avoid double-setup
        guard self.baseURL == nil else {
            if self.baseURL != baseURL {
                await teardownAndReload(baseURL: baseURL)
            }
            return
        }

        self.baseURL = baseURL

        // Inject auth cookies before loading
        await injectAuthCookies(for: baseURL)

        // Load the SPA at this tab's route
        let loadURL: URL
        if route == "/" {
            loadURL = baseURL
        } else {
            loadURL = baseURL.appendingPathComponent(route)
        }
        webPage.load(URLRequest(url: loadURL))

        // Start observing navigation events
        observeNavigationEvents()
    }

    // MARK: - Navigation Event Observation

    private func observeNavigationEvents() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in self.webPage.navigations {
                    switch event {
                    case .committed:
                        // Inject bridge polyfill and platform detection as soon as content starts loading
                        await self.injectBridgePolyfill()

                    case .finished:
                        self.isLoaded = true
                        self.loadError = nil

                        // Sync theme on load
                        self.syncTheme()

                        // Signal the web frontend to re-check auth
                        _ = try? await self.webPage.callJavaScript("window.__nativeBridge?.recheckAuth()")

                    default:
                        break
                    }
                }
            } catch let error as WebPage.NavigationError {
                switch error {
                case .failedProvisionalNavigation(let underlying):
                    self.isLoaded = false
                    self.loadError = underlying
                    print("[TabWebViewModel:\(self.route)] Provisional navigation failed: \(underlying.localizedDescription)")
                case .webContentProcessTerminated:
                    print("[TabWebViewModel:\(self.route)] WebView process terminated, reloading...")
                    self.isLoaded = false
                    self.bridgeInjected = false
                    self.webPage.reload()
                default:
                    self.loadError = error
                    print("[TabWebViewModel:\(self.route)] Navigation error: \(error)")
                }
            } catch {
                self.loadError = error
                print("[TabWebViewModel:\(self.route)] Navigation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bridge Injection

    @MainActor
    private func injectBridgePolyfill() async {
        guard !bridgeInjected else { return }
        bridgeInjected = true

        _ = try? await webPage.callJavaScript(NativeBridgeHandler.bridgePolyfillScript)

        // Also apply theme immediately
        syncTheme()
    }

    // MARK: - Navigation (for deep links only)

    /// Navigate the React Router to a given path (no page reload).
    /// Used for deep links that target a sub-path within this tab's route.
    @MainActor
    func navigateTo(path: String) {
        guard isLoaded else { return }

        let js = "window.__nativeBridge?.navigateTo('\(path.escapedForJS)')"
        Task {
            _ = try? await webPage.callJavaScript(js)
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

        let theme = isDark ? "dark" : "light"
        let js = "window.__nativeBridge?.setTheme('\(theme)')"
        Task {
            _ = try? await webPage.callJavaScript(js)
        }
    }

    // MARK: - Auth Cookie Management

    /// Inject the current auth tokens as cookies via JavaScript.
    @MainActor
    func injectAuthCookies(for baseURL: URL) async {
        guard let host = baseURL.host else { return }

        if let accessToken = AuthManager.shared.accessToken {
            let secure = baseURL.scheme == "https" ? "; Secure" : ""
            let cookie = HTTPCookie(properties: [
                .name: "access_token",
                .value: accessToken,
                .domain: host,
                .path: "/",
                .secure: baseURL.scheme == "https" ? "TRUE" : "FALSE",
            ])
            if let cookie {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    /// Update auth cookies after a token refresh.
    @MainActor
    func updateAuthCookies() async {
        guard let baseURL = baseURL else { return }
        await injectAuthCookies(for: baseURL)
    }

    // MARK: - Reload

    /// Reload the current page.
    @MainActor
    func reload() {
        loadError = nil
        bridgeInjected = false
        webPage.reload()
    }

    // MARK: - Teardown

    /// Create a new WebPage and reload from scratch.
    @MainActor
    func teardownAndReload(baseURL: URL) async {
        isLoaded = false
        loadError = nil
        bridgeInjected = false

        // Create a fresh WebPage with new configuration
        let config = WebViewConfiguration.create(bridgeHandler: bridgeHandler)
        self.webPage = WebPage(configuration: config)

        self.baseURL = baseURL
        await injectAuthCookies(for: baseURL)

        let loadURL: URL
        if route == "/" {
            loadURL = baseURL
        } else {
            loadURL = baseURL.appendingPathComponent(route)
        }
        webPage.load(URLRequest(url: loadURL))
        observeNavigationEvents()
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
