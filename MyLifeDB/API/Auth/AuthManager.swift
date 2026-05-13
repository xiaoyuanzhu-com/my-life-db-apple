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

    private(set) var state: AuthState = .unknown

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

    // New keychain key — distinct from the old JWT-era keys (`mylifedb.accessToken`,
    // `mylifedb.refreshToken`). On upgrade those old values are simply ignored
    // and overwritten on next login.
    private static let sessionTokenKey = "mylifedb.sessionToken"

    private(set) var accessToken: String? {
        didSet {
            if let token = accessToken {
                KeychainHelper.save(key: Self.sessionTokenKey, value: token)
            } else {
                KeychainHelper.delete(key: Self.sessionTokenKey)
            }
        }
    }

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
        accessToken = KeychainHelper.load(key: Self.sessionTokenKey)
        if accessToken == nil {
            state = .unauthenticated
        }
        // Otherwise leave .unknown so MyLifeDBApp's .task triggers checkAuth().
    }

    // MARK: - Auth Check (called on app launch)

    @MainActor
    func checkAuth() async {
        guard let token = accessToken else {
            state = .unauthenticated
            return
        }

        state = .checking

        switch await validateSession(token) {
        case .valid(let username):
            state = .authenticated(username)
        case .invalid:
            // Server explicitly rejected the session — clear it.
            accessToken = nil
            state = .unauthenticated
        case .connectionError:
            // Can't reach the server. Stay optimistic-authenticated so the
            // UI loads; subsequent API calls will surface real errors. Without
            // a server round-trip we have no username, fall back to "User".
            state = .authenticated("User")
        }
    }

    // MARK: - OAuth Completion

    @MainActor
    func handleOAuthCompletion(sessionToken: String) {
        self.accessToken = sessionToken

        // Optimistic transition: the gateway just minted this session, so it
        // *is* valid. Fetch the username from /gw/api/me in the background;
        // until then label the user "User".
        state = .authenticated("User")
        NotificationCenter.default.post(name: .authTokensDidChange, object: nil)

        Task { @MainActor [weak self] in
            guard let self else { return }
            if case .valid(let username) = await self.validateSession(sessionToken) {
                if case .authenticated = self.state {
                    self.state = .authenticated(username)
                }
            }
        }
    }

    // MARK: - Logout

    @MainActor
    func logout() async {
        if let token = accessToken {
            let url = baseURL.appendingPathComponent("gw/auth/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 5
            _ = try? await Self.authSession.data(for: request)
        }

        accessToken = nil
        KeychainHelper.deleteAll()
        LibraryTreeCache.shared.clear()
        state = .unauthenticated
        NotificationCenter.default.post(name: .authTokensDidChange, object: nil)
    }

    // MARK: - 401 Handler (called by APIClient)

    @MainActor
    func handleUnauthorized() async -> Bool {
        // Opaque sessions don't refresh — a 401 means the session is gone.
        // Clear local state so the next launch goes straight to LoginView.
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

    @MainActor
    func handleForeground() {
        guard isAuthenticated, let token = accessToken else { return }
        // Re-validate against the gateway opportunistically; if the session
        // was revoked while the app was backgrounded, surface that now
        // instead of waiting for the next API call to 401.
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch await self.validateSession(token) {
            case .valid(let username):
                if case .authenticated = self.state {
                    self.state = .authenticated(username)
                }
            case .invalid:
                await self.logout()
            case .connectionError:
                break
            }
        }
    }

    // MARK: - Refresh shim (called by NativeBridgeHandler)

    /// Compatibility shim for the web frontend's `requestTokenRefresh` bridge
    /// action. Opaque sessions don't refresh; returning false signals "no
    /// fresh token available" and the web fetch path falls back to its own
    /// error handling. The native APIClient's 401 handler will logout the
    /// user on the next request.
    @MainActor
    func refreshAccessToken() async -> Bool {
        return false
    }

    // MARK: - Private

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
                return .connectionError
            }

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
            return .connectionError
        }
    }
}
