//
//  TabWebViewModel.swift
//  MyLifeDB
//
//  Per-tab WebView model. Each web tab creates its own instance,
//  which owns an independent WebPage loaded at a fixed route.
//
//  Auth strategy: WKUserScript at documentStart injects the bridge polyfill,
//  access token, and feature flags BEFORE any page JS executes. The web
//  frontend reads window.__nativeAccessToken and adds Authorization: Bearer
//  headers via fetchWithRefresh. See hybrid.md for the full design.
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

    /// Posted by NativeBridgeHandler when the web frontend requests native navigation
    /// (e.g. clicking a file link in an agent session that should switch to the Library tab).
    static let nativeNavigateRequest = Notification.Name("nativeNavigateRequest")
}

// MARK: - TabWebViewModel

@Observable
final class TabWebViewModel {

    // MARK: - Configuration

    /// The route this WebView is pinned to (e.g. "/", "/agent").
    let route: String

    /// Feature flags to inject into the WebView before React mounts.
    let featureFlags: [String: Bool]

    // MARK: - Observable State

    /// The WebPage instance that backs the SwiftUI WebView.
    private(set) var webPage: WebPage

    /// Whether the initial page load has completed.
    private(set) var isLoaded = false

    /// Error from the last navigation attempt, if any.
    private(set) var loadError: Error?

    // MARK: - Non-observable State

    private var baseURL: URL?
    private var pendingNavigation: String?
    private var navigationTask: Task<Void, Never>?
    private var lastProcessTermination: Date?
    private static let processTerminationCooldown: TimeInterval = 10

    /// Shared user content controller. Holds the WKUserScript that injects
    /// the bridge polyfill + access token at documentStart. Persists across
    /// reloads; updated before each load/reload to use the freshest token.
    private let userContentController = WKUserContentController()

    // MARK: - Bridge

    let bridgeHandler = NativeBridgeHandler()

    // MARK: - Init

    init(route: String, featureFlags: [String: Bool] = [:]) {
        self.route = route
        self.featureFlags = featureFlags

        // Register the document-start user script with bridge polyfill + token + flags.
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )

        // Register the native bridge as a WKScriptMessageHandlerWithReply under
        // name "native". This is what backs window.webkit.messageHandlers.native
        // and lets postMessage(...) round-trip a Promise reply. Lives for the
        // lifetime of this WebView; not re-registered on reload (the WCC
        // persists across loads).
        userContentController.addScriptMessageHandler(
            bridgeHandler,
            contentWorld: .page,
            name: "native"
        )

        let config = WebViewConfiguration.create(
            userContentController: userContentController
        )
        self.webPage = WebPage(configuration: config)
        #if DEBUG
        self.webPage.isInspectable = true
        #endif
    }

    deinit {
        navigationTask?.cancel()
    }

    // MARK: - Setup

    @MainActor
    func setup(baseURL: URL) async {
        guard self.baseURL == nil else {
            if self.baseURL != baseURL {
                await teardownAndReload(baseURL: baseURL)
            }
            return
        }

        self.baseURL = baseURL

        // Refresh the user script with the latest token (may have changed since init).
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )

        // Also set cookies in WebKit store (belt-and-suspenders).
        await injectAuthCookiesViaWebKitStore(for: baseURL)

        let loadURL = resolveRoute(route, against: baseURL)
        webPage.load(URLRequest(url: loadURL))
        observeNavigationEvents()
    }

    // MARK: - WKUserScript Management

    /// Build and register the document-start user script on the given UCC.
    /// Called before every page load/reload to ensure the freshest token.
    private static func registerBridgeScript(
        on ucc: WKUserContentController,
        featureFlags: [String: Bool],
        accessToken: String?
    ) {
        ucc.removeAllUserScripts()

        var script = NativeBridgeHandler.bridgePolyfillScript

        // Apply the system theme to <html> at documentStart so the page paints
        // with the correct background from the first frame. Without this the
        // CSS `:root` light defaults render a white flash before
        // `__nativeBridge.setTheme()` (set up after React mounts) toggles the
        // `.dark` class.
        let isDark = currentIsDarkMode()
        script += """
            \n(function() {
                var d = '\(isDark ? "dark" : "light")';
                if (d === 'dark') {
                    document.documentElement.classList.add('dark');
                } else {
                    document.documentElement.classList.remove('dark');
                }
                document.documentElement.style.colorScheme = d;
            })();
            """

        if !featureFlags.isEmpty {
            let pairs = featureFlags
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            script += "\nwindow.__featureFlags = { \(pairs) };"
        }

        if let accessToken {
            script += "\nwindow.__nativeAccessToken = '\(accessToken.escapedForJS)';"
        }

        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        ucc.addUserScript(userScript)
    }

    /// Current system dark-mode state. Used both to seed the documentStart
    /// script and to keep the running page in sync via `syncTheme()`.
    private static func currentIsDarkMode() -> Bool {
        #if os(iOS)
        return UITraitCollection.current.userInterfaceStyle == .dark
        #elseif os(macOS)
        return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
        return false
        #endif
    }

    // MARK: - Navigation Event Observation

    private func observeNavigationEvents() {
        navigationTask?.cancel()

        navigationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let navigations = self.webPage.navigations
                do {
                    for try await event in navigations {
                        guard !Task.isCancelled else { return }
                        switch event {
                        case .committed:
                            // Bridge polyfill + token + flags already injected
                            // via WKUserScript at documentStart.
                            // Only inject safe area insets (requires UIKit at runtime).
                            await self.injectSafeAreaInsets()
                            self.syncTheme()

                        case .finished:
                            self.isLoaded = true
                            self.loadError = nil
                            self.syncTheme()

                            // Safety net: trigger auth recheck after React mounts.
                            // With WKUserScript, the first checkAuth() should succeed,
                            // but late-mounting components may need this signal.
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled, let self else { return }
                                _ = try? await self.webPage.callJavaScript("window.__nativeRecheckAuth?.()")
                            }

                            if let pending = self.pendingNavigation {
                                self.navigateTo(path: pending)
                            }

                        default:
                            break
                        }
                    }
                    break
                } catch let error as WebPage.NavigationError {
                    guard !Task.isCancelled else { return }
                    switch error {
                    case .failedProvisionalNavigation(let underlying):
                        self.isLoaded = false
                        self.loadError = underlying
                        print("[TabWebViewModel:\(self.route)] Provisional navigation failed: \(underlying.localizedDescription)")
                    case .webContentProcessTerminated:
                        if let last = self.lastProcessTermination,
                           Date().timeIntervalSince(last) < Self.processTerminationCooldown {
                            self.isLoaded = false
                            try? await Task.sleep(for: .seconds(Self.processTerminationCooldown))
                            continue
                        }
                        self.lastProcessTermination = Date()
                        self.isLoaded = false

                        // Refresh user script + cookies before reload
                        Self.registerBridgeScript(
                            on: self.userContentController,
                            featureFlags: self.featureFlags,
                            accessToken: AuthManager.shared.accessToken
                        )
                        if let baseURL = self.baseURL {
                            await self.injectAuthCookiesViaWebKitStore(for: baseURL)
                        }
                        self.webPage.reload()
                    default:
                        self.loadError = error
                        print("[TabWebViewModel:\(self.route)] Navigation error: \(error)")
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.loadError = error
                    print("[TabWebViewModel:\(self.route)] Navigation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Navigation (for deep links only)

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

    @MainActor
    func loadPath(_ path: String) {
        guard let baseURL else { return }
        let url = resolveRoute(path, against: baseURL)
        pendingNavigation = nil

        // Refresh user script with latest token before loading new page
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )
        webPage.load(URLRequest(url: url))
    }

    // MARK: - Safe Area Inset Injection

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

    @MainActor
    func syncTheme() {
        let theme = Self.currentIsDarkMode() ? "dark" : "light"
        let js = "window.__nativeBridge?.setTheme('\(theme)')"
        Task {
            _ = try? await webPage.callJavaScript(js)
        }
    }

    // MARK: - Auth Token Management

    /// Update the access token in the running page's JS context.
    /// Called after token refresh to update window.__nativeAccessToken
    /// so subsequent fetch() calls use the fresh token.
    @MainActor
    private func updateAccessTokenInJS() async {
        if let accessToken = AuthManager.shared.accessToken {
            _ = try? await webPage.callJavaScript(
                "window.__nativeAccessToken = '\(accessToken.escapedForJS)'"
            )
        }
    }

    /// Push fresh auth token to the WebView (no recheck).
    /// Use from `.authTokensDidChange` to avoid refresh loop.
    @MainActor
    func pushAuthCookies() async {
        guard let baseURL else { return }
        // Update user script so future reloads use fresh token
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )
        // Update running page
        await injectAuthCookiesViaWebKitStore(for: baseURL)
        await updateAccessTokenInJS()
    }

    /// Push fresh auth token AND signal the web frontend to re-check auth.
    /// Use on foreground resume (scenePhase), NOT from token-change notifications.
    @MainActor
    func pushAuthCookiesAndRecheck() async {
        guard let baseURL else { return }
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )
        await injectAuthCookiesViaWebKitStore(for: baseURL)
        await updateAccessTokenInJS()
        _ = try? await webPage.callJavaScript("window.__nativeRecheckAuth?.()")
    }

    // MARK: - Cookie Management (belt-and-suspenders)

    /// Inject auth cookies via WebKit's cookie store (WKHTTPCookieStore).
    /// Supplementary to the Authorization header approach — ensures cookies
    /// are present for any code paths that don't go through fetchWithRefresh
    /// (e.g. nested iframe navigations like `<iframe src="/raw/.generated/...">`
    /// inside srcdoc preview iframes, which can't attach Authorization headers).
    ///
    /// Two attributes are critical for WKWebView cookie delivery:
    ///
    /// - **SameSite=Lax**: Must be set explicitly. Without it, WKWebView may
    ///   not send cookies for same-origin iframe navigations originating from
    ///   srcdoc contexts. Regular Safari defaults unset SameSite to Lax via
    ///   the Set-Cookie header, but programmatic HTTPCookie creation does not.
    ///
    /// - **Secure flag**: Must be *omitted* (not set to "FALSE") for HTTP.
    ///   Apple docs: "String value must be either TRUE or there should be no
    ///   value." Setting "FALSE" still marks the cookie as secure, causing it
    ///   to be withheld from HTTP requests.
    @MainActor
    private func injectAuthCookiesViaWebKitStore(for baseURL: URL) async {
        guard let host = baseURL.host else { return }
        let auth = AuthManager.shared
        let isSecure = baseURL.scheme == "https"
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore

        if let accessToken = auth.accessToken {
            let expiry = auth.accessTokenExpiry ?? Date().addingTimeInterval(3600)
            var accessProps: [HTTPCookiePropertyKey: Any] = [
                .name: "access_token",
                .value: accessToken,
                .domain: host,
                .path: "/",
                .expires: expiry,
                .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax,
            ]
            if isSecure { accessProps[.secure] = "TRUE" }
            if let cookie = HTTPCookie(properties: accessProps) {
                await cookieStore.setCookie(cookie)
            }
        }

        if let refreshToken = auth.refreshTokenForCookie {
            var refreshProps: [HTTPCookiePropertyKey: Any] = [
                .name: "refresh_token",
                .value: refreshToken,
                .domain: host,
                .path: "/api/system/oauth",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 30),
                .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax,
            ]
            if isSecure { refreshProps[.secure] = "TRUE" }
            if let cookie = HTTPCookie(properties: refreshProps) {
                await cookieStore.setCookie(cookie)
            }
        }
    }

    // MARK: - Cleanup

    @MainActor
    func cancelObservation() {
        navigationTask?.cancel()
        navigationTask = nil
    }

    // MARK: - Reload

    @MainActor
    func reload() {
        loadError = nil
        // Refresh user script with latest token before reload
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )
        webPage.reload()
    }

    // MARK: - Teardown

    @MainActor
    func teardownAndReload(baseURL: URL) async {
        isLoaded = false
        loadError = nil

        self.baseURL = baseURL

        // Refresh user script with latest token
        Self.registerBridgeScript(
            on: userContentController,
            featureFlags: featureFlags,
            accessToken: AuthManager.shared.accessToken
        )

        let config = WebViewConfiguration.create(
            userContentController: userContentController
        )
        self.webPage = WebPage(configuration: config)
        #if DEBUG
        self.webPage.isInspectable = true
        #endif

        await injectAuthCookiesViaWebKitStore(for: baseURL)

        let loadURL = resolveRoute(route, against: baseURL)
        webPage.load(URLRequest(url: loadURL))
        observeNavigationEvents()
    }
}

// MARK: - URL Helpers

/// Resolve a frontend route (e.g. "/", "/agent", "/agent/auto?edit=foo")
/// against the base URL. Uses URL(string:relativeTo:) so that routes
/// containing query strings or fragments are parsed correctly —
/// `appendingPathComponent` would percent-encode "?" and "#".
private func resolveRoute(_ route: String, against baseURL: URL) -> URL {
    if route == "/" { return baseURL }
    if let resolved = URL(string: route, relativeTo: baseURL)?.absoluteURL {
        return resolved
    }
    return baseURL.appendingPathComponent(route)
}

// MARK: - String Extension for JS Escaping

private extension String {
    var escapedForJS: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
