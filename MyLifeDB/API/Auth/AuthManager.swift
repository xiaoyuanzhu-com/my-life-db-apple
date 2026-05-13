//
//  AuthManager.swift
//  MyLifeDB
//
//  Central authentication state manager. The app authenticates to the cloud
//  gateway (`my.xiaoyuanzhu.com`), which mints an opaque session id over
//  `/gw/auth/login` → `/gw/auth/callback` → `mylifedb://oauth/callback`. The
//  session id is the only credential — no JWT, no refresh, no expiry math.
//  When the gateway returns 401, the session is gone and the user re-logs in.
//
//  STATE MACHINE
//  The state transitions are intentionally minimal to prevent races:
//
//    init                    → .unauthenticated (no token) | .unknown (token in keychain)
//    checkAuth (.unknown)    → .authenticated (always; optimistic)
//    handleOAuthCompletion   → .authenticated (always; optimistic)
//    handleUnauthorized      → .unauthenticated (skip during fresh-login window)
//    logout (user-initiated) → .unauthenticated
//
//  No path proactively demotes .authenticated → .unauthenticated based on a
//  validation result. The only logout vector is an explicit 401 routed through
//  APIClient (and even that is suppressed for a short window after token
//  issuance, so racy background tasks at login time can't kick the user out).
//

import Foundation
import Observation

// MARK: - Notifications

extension Notification.Name {
    /// Posted after AuthManager completes OAuth login or logs out.
    /// WebView models observe this to push fresh cookies to the web layer.
    static let authTokensDidChange = Notification.Name("authTokensDidChange")
}

@Observable
final class AuthManager {

    // MARK: - Singleton

    static let shared = AuthManager()

    // MARK: - Auth State

    enum AuthState: Equatable {
        case unknown
        case checking
        case authenticated(String) // username
        case provisioning(String)  // username — backend instance being set up
        case unauthenticated
    }

    private(set) var state: AuthState = .unknown {
        didSet {
            print("[AuthManager] state: \(oldValue) -> \(state)")
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var username: String? {
        if case .authenticated(let name) = state { return name }
        if case .provisioning(let name) = state { return name }
        return nil
    }

    // MARK: - Token

    // Keychain key — distinct from the old JWT-era keys (`mylifedb.accessToken`,
    // `mylifedb.refreshToken`). On upgrade those old values are ignored and
    // overwritten on next login.
    private static let sessionTokenKey = "mylifedb.sessionToken"

    private(set) var accessToken: String? {
        didSet {
            if let token = accessToken {
                KeychainHelper.save(key: Self.sessionTokenKey, value: token)
                tokenIssuedAt = Date()
            } else {
                KeychainHelper.delete(key: Self.sessionTokenKey)
            }
        }
    }

    /// When the current token was set. Used as a fresh-login grace window —
    /// racy background tasks that 401 right after login (e.g. a request that
    /// went out before WebKit picked up the new cookie, or a network blip
    /// the system surfaces as 401) must not log the user out within this
    /// window. After the window expires, real 401s are honored.
    @ObservationIgnored
    private var tokenIssuedAt: Date?
    private static let freshLoginGrace: TimeInterval = 10

    // MARK: - Base URL

    var baseURL: URL {
        let urlString = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "https://my.xiaoyuanzhu.com"
        return URL(string: urlString) ?? URL(string: "https://my.xiaoyuanzhu.com")!
    }

    // MARK: - Dedicated Auth Session

    /// Ephemeral session for auth requests. Cookies disabled to prevent
    /// dual-storage — Keychain is the single source of truth.
    private static let authSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    // MARK: - Init

    private init() {
        let token = KeychainHelper.load(key: Self.sessionTokenKey)
        accessToken = token
        if token == nil {
            state = .unauthenticated
        }
        // Otherwise leave .unknown so MyLifeDBApp's .task triggers checkAuth().
    }

    // MARK: - Auth Check (called on app launch when state is .unknown)

    /// Optimistic launch path: if we have a token in keychain, trust it.
    /// The first real API call will surface a 401 if the server has revoked
    /// the session — at which point handleUnauthorized clears state.
    @MainActor
    func checkAuth() async {
        guard accessToken != nil else {
            state = .unauthenticated
            return
        }
        state = .authenticated("User")
        // Refine the username in the background; never demote on failure.
        refreshUsernameInBackground()
    }

    // MARK: - OAuth Completion

    @MainActor
    func handleOAuthCompletion(sessionToken: String) {
        print("[AuthManager] handleOAuthCompletion — transitioning to .authenticated")
        self.accessToken = sessionToken
        state = .authenticated("User")
        NotificationCenter.default.post(name: .authTokensDidChange, object: nil)
        refreshUsernameInBackground()
    }

    // MARK: - Logout

    @MainActor
    func logout() async {
        print("[AuthManager] logout() called")
        if let token = accessToken {
            let url = baseURL.appendingPathComponent("gw/auth/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 5
            _ = try? await Self.authSession.data(for: request)
        }

        accessToken = nil
        tokenIssuedAt = nil
        KeychainHelper.deleteAll()
        LibraryTreeCache.shared.clear()
        state = .unauthenticated
        NotificationCenter.default.post(name: .authTokensDidChange, object: nil)
    }

    // MARK: - 401 Handler (called by APIClient)

    /// Called by APIClient when a request returns 401. Opaque sessions don't
    /// refresh, so a genuine 401 means logout. BUT — racy background tasks
    /// firing at login time (cookies not yet in the store, a transient
    /// network blip, etc.) can produce 401-like outcomes that aren't real
    /// auth failures. We suppress logout for `freshLoginGrace` seconds after
    /// the token is set; after that, real 401s logout normally.
    @MainActor
    func handleUnauthorized() async -> Bool {
        if let issuedAt = tokenIssuedAt,
           Date().timeIntervalSince(issuedAt) < Self.freshLoginGrace {
            print("[AuthManager] handleUnauthorized: within fresh-login grace, suppressing logout")
            return false
        }
        print("[AuthManager] handleUnauthorized: logging out")
        await logout()
        return false
    }

    // MARK: - 503 Provisioning Handler (called by APIClient)

    @MainActor
    func handleProvisioning() async {
        if case .provisioning = state { return }
        let currentUsername = username ?? "User"
        state = .provisioning(currentUsername)
    }

    @MainActor
    func handleProvisioningComplete() async {
        if case .provisioning(let name) = state {
            state = .authenticated(name)
        }
    }

    // MARK: - Scene Phase Handling

    /// Opportunistic username refresh on foreground resume. Never demotes
    /// state — if the server says the session is invalid, the next real API
    /// call will 401 and handleUnauthorized handles it.
    @MainActor
    func handleForeground() {
        print("[AuthManager] handleForeground entry, isAuthenticated=\(isAuthenticated)")
        guard isAuthenticated else { return }
        refreshUsernameInBackground()
    }

    // MARK: - Refresh shim (called by NativeBridgeHandler)

    /// Compatibility shim for the web frontend's `requestTokenRefresh` bridge
    /// action. Opaque sessions don't refresh; returning false signals "no
    /// fresh token available" and the web fetch path falls back to its own
    /// error handling.
    @MainActor
    func refreshAccessToken() async -> Bool {
        return false
    }

    // MARK: - Private

    /// Fire-and-forget call to `/gw/api/me` to refine the username. Never
    /// demotes state — on .invalid we just leave the optimistic "User"
    /// label in place; the next real API call will 401 and the proper
    /// logout path runs.
    private func refreshUsernameInBackground() {
        guard let token = accessToken else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.validateSession(token)
            print("[AuthManager] refreshUsernameInBackground result: \(result)")
            if case .valid(let username) = result,
               case .authenticated = self.state {
                self.state = .authenticated(username)
            }
        }
    }

    private enum SessionValidationResult {
        case valid(String) // username
        case invalid
        case connectionError
    }

    /// Validate the session against the gateway's `/gw/api/me` endpoint.
    /// 200 → valid with username; 401 → invalid; anything else → transient.
    private func validateSession(_ token: String) async -> SessionValidationResult {
        do {
            let url = baseURL.appendingPathComponent("gw/api/me")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await Self.authSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[validateSession] non-HTTP response")
                return .connectionError
            }
            print("[validateSession] HTTP \(httpResponse.statusCode) from \(url.absoluteString)")

            if httpResponse.statusCode == 401 {
                return .invalid
            }
            guard httpResponse.statusCode == 200 else {
                return .connectionError
            }

            // /gw/api/me wraps the body as { data: { username, ... } }
            guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = envelope["data"] as? [String: Any],
                  let username = payload["username"] as? String, !username.isEmpty else {
                return .valid("User")
            }
            return .valid(username)
        } catch {
            print("[validateSession] error: \(error)")
            return .connectionError
        }
    }
}
