//
//  AuthManager.swift
//  MyLifeDB
//
//  Central authentication state manager.
//  Handles OAuth login, token storage, reactive refresh (401 + foreground resume), and logout.
//

import Foundation
import Observation

// MARK: - Notifications

extension Notification.Name {
    /// Posted after AuthManager successfully refreshes tokens or completes OAuth login.
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
        case unauthenticated
    }

    private(set) var state: AuthState = .unknown

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    var username: String? {
        if case .authenticated(let name) = state { return name }
        return nil
    }

    // MARK: - Tokens

    private static let accessTokenKey = "mylifedb.accessToken"
    private static let refreshTokenKey = "mylifedb.refreshToken"

    private(set) var accessToken: String? {
        didSet {
            if let token = accessToken {
                KeychainHelper.save(key: Self.accessTokenKey, value: token)
            } else {
                KeychainHelper.delete(key: Self.accessTokenKey)
            }
        }
    }

    private var refreshToken: String? {
        didSet {
            if let token = refreshToken {
                KeychainHelper.save(key: Self.refreshTokenKey, value: token)
            } else {
                KeychainHelper.delete(key: Self.refreshTokenKey)
            }
        }
    }

    // MARK: - Cookie Helpers (used by TabWebViewModel for cookie injection)

    /// The refresh token for WebView cookie injection.
    /// Native is the single auth owner; the cookie is an emergency fallback.
    /// WebView delegates refresh to native via the bridge (requestTokenRefresh).
    var refreshTokenForCookie: String? { refreshToken }

    /// Seconds until the access token expires (for cookie max-age). Defaults to 3600.
    var accessTokenMaxAge: Int {
        guard let token = accessToken, let exp = jwtExpiration(token) else { return 3600 }
        return max(Int(exp.timeIntervalSinceNow), 0)
    }

    /// The access token's expiry date (for cookie .expires property).
    var accessTokenExpiry: Date? {
        guard let token = accessToken else { return nil }
        return jwtExpiration(token)
    }

    // MARK: - Refresh

    /// In-flight refresh task. Concurrent callers await the same task
    /// instead of being rejected (single-flight pattern).
    private var refreshInFlight: Task<RefreshResult, Never>?

    // MARK: - Dedicated Auth Session

    /// Ephemeral session for auth requests. Cookies disabled to prevent
    /// dual-storage — Keychain is the single source of truth for tokens.
    private static let authSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    // MARK: - Base URL

    /// The backend base URL (configurable via Settings → Server).
    /// Used by both APIClient and TabWebViewModel.
    var baseURL: URL {
        let urlString = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "https://my.xiaoyuanzhu.com"
        return URL(string: urlString) ?? URL(string: "https://my.xiaoyuanzhu.com")!
    }

    // MARK: - Init

    private init() {
        // Load tokens from Keychain
        accessToken = KeychainHelper.load(key: Self.accessTokenKey)
        refreshToken = KeychainHelper.load(key: Self.refreshTokenKey)
    }

    // MARK: - Auth Check (called on app launch)

    @MainActor
    func checkAuth() async {
        state = .checking

        // If we have an access token, validate it
        if let token = accessToken {
            let result = await validateToken(token)
            switch result {
            case .valid(let username):
                state = .authenticated(username)
                return
            case .invalid, .noOAuth:
                // Token expired or OAuth not configured, try refresh
                if await tryRefresh() == .success {
                    return
                }
                state = .unauthenticated
                return
            case .connectionError:
                // Can't reach server - stay unauthenticated so user can fix server URL
                state = .unauthenticated
                return
            }
        }

        // Try refresh if we have a refresh token
        if refreshToken != nil {
            if await tryRefresh() == .success {
                return
            }
        }

        state = .unauthenticated
    }

    // MARK: - OAuth Completion

    @MainActor
    func handleOAuthCompletion(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken

        // Validate and extract username
        Task {
            let result = await validateToken(accessToken)
            switch result {
            case .valid(let username):
                state = .authenticated(username)
            default:
                // Token was just issued, shouldn't fail. But handle gracefully.
                state = .authenticated("User")
            }
            NotificationCenter.default.post(name: .authTokensDidChange, object: nil)
        }
    }

    // MARK: - Token Refresh

    @MainActor
    func refreshAccessToken() async -> Bool {
        return await tryRefresh() == .success
    }

    /// Outcome of a token refresh attempt. Distinguishes "refresh token is
    /// confirmed invalid" (server returned 401) from transient failures
    /// (network error, server 5xx) so callers can decide whether to logout.
    private enum RefreshResult {
        case success
        case rejected   // Server confirmed refresh token is invalid (401)
        case failed     // Transient error — network, timeout, server error, etc.
    }

    @MainActor
    private func tryRefresh() async -> RefreshResult {
        // Single-flight: if a refresh is already in progress, wait for it
        if let existing = refreshInFlight {
            return await existing.value
        }

        guard let refreshToken = refreshToken else { return .failed }

        let task = Task<RefreshResult, Never> { @MainActor [weak self] in
            guard let self else { return .failed }

            do {
                let url = self.baseURL.appendingPathComponent("api/oauth/refresh")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: ["refresh_token": refreshToken]
                )
                request.timeoutInterval = 10

                let (data, response) = try await Self.authSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else { return .failed }

                // 401 = server explicitly rejected the refresh token
                if httpResponse.statusCode == 401 {
                    return .rejected
                }

                guard httpResponse.statusCode == 200 else { return .failed }

                // Parse tokens from JSON response body
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return .failed
                }

                if let newAccess = json["access_token"] as? String, !newAccess.isEmpty {
                    self.accessToken = newAccess
                }
                if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
                    self.refreshToken = newRefresh
                }

                // Validate new token and update state
                if let token = self.accessToken {
                    let result = await self.validateToken(token)
                    if case .valid(let username) = result {
                        self.state = .authenticated(username)
                        NotificationCenter.default.post(name: .authTokensDidChange, object: nil)
                        return .success
                    }
                }

                // Even if validation fails, if we got new tokens, consider it success
                if self.accessToken != nil {
                    NotificationCenter.default.post(name: .authTokensDidChange, object: nil)
                    return .success
                }

                return .failed
            } catch {
                return .failed
            }
        }

        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        return result
    }

    // MARK: - Logout

    @MainActor
    func logout() async {
        // Call backend logout (best-effort)
        do {
            let url = baseURL.appendingPathComponent("api/oauth/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 5
            _ = try? await Self.authSession.data(for: request)
        }

        // Clear local state
        accessToken = nil
        refreshToken = nil
        KeychainHelper.deleteAll()
        state = .unauthenticated
    }

    // MARK: - 401 Handler (called by APIClient)

    @MainActor
    func handleUnauthorized() async -> Bool {
        let result = await tryRefresh()
        switch result {
        case .success:
            return true // Caller should retry the request
        case .rejected:
            // Refresh token is confirmed invalid — full logout
            await logout()
            return false
        case .failed:
            // Transient error (network, server 5xx, etc.) — don't destroy
            // tokens, the user may recover on retry or foreground resume.
            return false
        }
    }

    // MARK: - Scene Phase Handling

    @MainActor
    func handleForeground() {
        guard isAuthenticated else { return }

        // Check if token needs refresh
        if let token = accessToken, isTokenExpiringSoon(token) {
            Task {
                _ = await tryRefresh()
            }
        }
    }

    // MARK: - Private Helpers

    private enum TokenValidationResult {
        case valid(String) // username
        case invalid
        case noOAuth
        case connectionError
    }

    private func validateToken(_ token: String) async -> TokenValidationResult {
        do {
            let url = baseURL.appendingPathComponent("api/oauth/token")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            let (data, response) = try await Self.authSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .connectionError
            }

            if httpResponse.statusCode == 404 {
                return .noOAuth
            }

            guard httpResponse.statusCode == 200 else {
                return .invalid
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .invalid
            }

            if json["authenticated"] as? Bool == true {
                let username = json["username"] as? String ?? "User"
                return .valid(username)
            }

            return .invalid
        } catch {
            return .connectionError
        }
    }

    // MARK: - JWT Helpers

    private func isTokenExpiringSoon(_ token: String) -> Bool {
        guard let exp = jwtExpiration(token) else { return true }
        return exp.timeIntervalSinceNow < 120 // Less than 2 minutes
    }

    private func jwtExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
        // Pad base64 string
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        // JWT uses base64url encoding
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }
}
