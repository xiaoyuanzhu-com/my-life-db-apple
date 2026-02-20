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

    /// Feature flags to inject into the WebView before React mounts.
    /// Keys map to FeatureFlags properties on the web side (e.g. "sessionSidebar").
    /// Only flags explicitly set here are injected; missing flags keep their web-side defaults.
    let featureFlags: [String: Bool]

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

    /// Queued path to navigate to once the page finishes loading.
    /// Set when `navigateTo` is called while `isLoaded` is false.
    private var pendingNavigation: String?

    /// The running navigation observation task.  Stored so it can be
    /// cancelled when `teardownAndReload` replaces the WebPage, preventing
    /// the old task from keeping `self` alive via the async `for await` loop.
    private var navigationTask: Task<Void, Never>?

    // MARK: - Bridge

    let bridgeHandler = NativeBridgeHandler()

    // MARK: - Init

    init(route: String, featureFlags: [String: Bool] = [:]) {
        self.route = route
        self.featureFlags = featureFlags
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

        // Inject auth cookies via cookie store before loading (awaited for sync)
        injectAuthCookiesViaStore(for: baseURL)

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
        // Cancel any previous observation task so it doesn't keep self alive
        // via the long-lived `for await` loop on the old WebPage's navigations.
        navigationTask?.cancel()

        navigationTask = Task { @MainActor [weak self] in
            guard let navigations = self?.webPage.navigations else { return }
            do {
                for try await event in navigations {
                    guard let self, !Task.isCancelled else { return }
                    switch event {
                    case .committed:
                        // Inject bridge polyfill and platform detection as soon as content starts loading
                        await self.injectBridgePolyfill()

                        // Inject auth cookies via JS immediately — ensures cookies are present
                        // before React's first fetch, bypassing HTTPCookieStorage sync delay
                        await self.injectAuthCookiesViaJS()

                        // Inject real safe area insets as CSS custom properties.
                        // Must happen before React renders so fullscreen overlays
                        // can position elements outside the Dynamic Island / notch.
                        await self.injectSafeAreaInsets()

                    case .finished:
                        self.isLoaded = true
                        self.loadError = nil

                        // Sync theme on load
                        self.syncTheme()

                        // Signal the web frontend to re-check auth after a short delay.
                        // The delay ensures React has mounted and registered its
                        // "native-recheck-auth" event listener.
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(200))
                            guard !Task.isCancelled else { return }
                            _ = try? await self?.webPage.callJavaScript("window.__nativeRecheckAuth?.()")
                        }

                        // Flush any navigation that was queued while loading
                        if let pending = self.pendingNavigation {
                            self.navigateTo(path: pending)
                        }

                    default:
                        break
                    }
                }
            } catch let error as WebPage.NavigationError {
                guard let self, !Task.isCancelled else { return }
                switch error {
                case .failedProvisionalNavigation(let underlying):
                    self.isLoaded = false
                    self.loadError = underlying
                    print("[TabWebViewModel:\(self.route)] Provisional navigation failed: \(underlying.localizedDescription)")
                case .webContentProcessTerminated:
                    print("[TabWebViewModel:\(self.route)] WebView process terminated, reloading...")
                    self.isLoaded = false
                    self.bridgeInjected = false
                    // Re-inject cookies via store before reload (JS not available after crash)
                    if let baseURL = self.baseURL {
                        self.injectAuthCookiesViaStore(for: baseURL)
                    }
                    self.webPage.reload()
                default:
                    self.loadError = error
                    print("[TabWebViewModel:\(self.route)] Navigation error: \(error)")
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
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

        var script = NativeBridgeHandler.bridgePolyfillScript

        // Inject feature flags if any are configured.
        // Sets window.__featureFlags before React mounts so the web frontend
        // can read them synchronously during initial render.
        if !featureFlags.isEmpty {
            let pairs = featureFlags
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            script += "\nwindow.__featureFlags = { \(pairs) };"
        }

        _ = try? await webPage.callJavaScript(script)

        // Also apply theme immediately
        syncTheme()
    }

    // MARK: - Navigation (for deep links only)

    /// Navigate the React Router to a given path (no page reload).
    /// Used for deep links that target a sub-path within this tab's route.
    /// If the page hasn't finished loading yet, the navigation is queued
    /// and will be dispatched automatically once the load completes.
    @MainActor
    func navigateTo(path: String) {
        guard isLoaded else {
            pendingNavigation = path
            return
        }
        pendingNavigation = nil

        let js = "window.__nativeBridge?.navigateTo('\(path.escapedForJS)')"
        Task {
            _ = try? await webPage.callJavaScript(js)
        }
    }

    /// Load a path directly via URL (full page load). Use when JS bridge
    /// navigation may not work (e.g. WebPage not attached to a view).
    @MainActor
    func loadPath(_ path: String) {
        guard let baseURL else { return }
        let url: URL
        if path == "/" {
            url = baseURL
        } else {
            url = baseURL.appendingPathComponent(path)
        }
        pendingNavigation = nil
        bridgeInjected = false
        webPage.load(URLRequest(url: url))
    }

    // MARK: - Safe Area Inset Injection

    /// Push the device's real safe area insets to the WebView as CSS custom properties.
    /// `.ignoresSafeArea()` on the SwiftUI WebView zeroes out the UIView's safeAreaInsets,
    /// which causes CSS `env(safe-area-inset-*)` to return 0px. This method reads the
    /// actual insets from the key window and injects them as `--native-sat/sar/sab/sal`
    /// so web content can use them as a fallback.
    @MainActor
    func injectSafeAreaInsets() async {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.keyWindow else { return }
        let insets = window.safeAreaInsets
        let js = """
            (function() {
                var s = document.documentElement.style;
                s.setProperty('--native-sat', '\(insets.top)px');
                s.setProperty('--native-sar', '\(insets.right)px');
                s.setProperty('--native-sab', '\(insets.bottom)px');
                s.setProperty('--native-sal', '\(insets.left)px');
            })();
            """
        _ = try? await webPage.callJavaScript(js)
        #endif
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

    /// Inject auth cookies via `document.cookie` JavaScript evaluation.
    /// This is the preferred runtime method — takes effect immediately in the
    /// WebView's JS context, bypassing HTTPCookieStorage sync delays.
    /// Requires a loaded page (JS evaluation needs a document).
    @MainActor
    private func injectAuthCookiesViaJS() async {
        let auth = AuthManager.shared
        let isSecure = baseURL?.scheme == "https"
        let secureFlag = isSecure ? " secure;" : ""

        if let accessToken = auth.accessToken {
            let maxAge = auth.accessTokenMaxAge
            let js = "document.cookie = 'access_token=\(accessToken.escapedForJS); path=/; max-age=\(maxAge);\(secureFlag) samesite=lax'"
            _ = try? await webPage.callJavaScript(js)
        }

        if let refreshToken = auth.refreshTokenForCookie {
            let js = "document.cookie = 'refresh_token=\(refreshToken.escapedForJS); path=/api/oauth; max-age=2592000;\(secureFlag) samesite=lax'"
            _ = try? await webPage.callJavaScript(js)
        }
    }

    /// Inject auth cookies via HTTPCookieStorage (system cookie store).
    /// Used before initial page load when JS evaluation is not yet available.
    /// Sets both cookies with explicit expiry (never session cookies).
    @MainActor
    func injectAuthCookiesViaStore(for baseURL: URL) {
        guard let host = baseURL.host else { return }
        let auth = AuthManager.shared
        let isSecure = baseURL.scheme == "https"

        if let accessToken = auth.accessToken {
            let expiry = auth.accessTokenExpiry ?? Date().addingTimeInterval(3600)
            let cookie = HTTPCookie(properties: [
                .name: "access_token",
                .value: accessToken,
                .domain: host,
                .path: "/",
                .expires: expiry,
                .secure: isSecure ? "TRUE" : "FALSE",
            ])
            if let cookie { HTTPCookieStorage.shared.setCookie(cookie) }
        }

        if let refreshToken = auth.refreshTokenForCookie {
            let cookie = HTTPCookie(properties: [
                .name: "refresh_token",
                .value: refreshToken,
                .domain: host,
                .path: "/api/oauth",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 30), // 30 days
                .secure: isSecure ? "TRUE" : "FALSE",
            ])
            if let cookie { HTTPCookieStorage.shared.setCookie(cookie) }
        }
    }

    /// Push fresh auth cookies to the WebView via JS and signal re-check.
    /// Call this after token refresh or on foreground resume.
    @MainActor
    func pushAuthCookiesAndRecheck() async {
        guard baseURL != nil else { return }
        await injectAuthCookiesViaJS()
        _ = try? await webPage.callJavaScript("window.__nativeRecheckAuth?.()")
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
        injectAuthCookiesViaStore(for: baseURL)

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
