//
//  AuthManager.swift
//  MyLifeDB
//
//  Central authentication state manager.
//  Handles OAuth login, token storage, auto-refresh, and 401 recovery.
//

import Foundation
import Observation

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

    // MARK: - Refresh Timer

    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false

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
                scheduleRefresh()
                return
            case .invalid, .noOAuth:
                // Token expired or OAuth not configured, try refresh
                if await tryRefresh() {
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
            if await tryRefresh() {
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
                scheduleRefresh()
            default:
                // Token was just issued, shouldn't fail. But handle gracefully.
                state = .authenticated("User")
                scheduleRefresh()
            }
        }
    }

    // MARK: - Token Refresh

    @MainActor
    func refreshAccessToken() async -> Bool {
        return await tryRefresh()
    }

    @MainActor
    private func tryRefresh() async -> Bool {
        guard let refreshToken = refreshToken, !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let url = baseURL.appendingPathComponent("api/oauth/refresh")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("refresh_token=\(refreshToken)", forHTTPHeaderField: "Cookie")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return false }

            guard httpResponse.statusCode == 200 else { return false }

            // Parse tokens from JSON response body
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }

            if let newAccess = json["access_token"] as? String, !newAccess.isEmpty {
                self.accessToken = newAccess
            }
            if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
                self.refreshToken = newRefresh
            }

            // Validate new token and update state
            if let token = self.accessToken {
                let result = await validateToken(token)
                if case .valid(let username) = result {
                    state = .authenticated(username)
                    scheduleRefresh()
                    return true
                }
            }

            // Even if validation fails, if we got new tokens, consider it success
            if self.accessToken != nil {
                scheduleRefresh()
                return true
            }

            return false
        } catch {
            return false
        }
    }

    // MARK: - Logout

    @MainActor
    func logout() async {
        // Cancel refresh timer
        refreshTask?.cancel()
        refreshTask = nil

        // Call backend logout (best-effort)
        do {
            let url = baseURL.appendingPathComponent("api/oauth/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 5
            _ = try? await URLSession.shared.data(for: request)
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
        // Try refresh once
        if await tryRefresh() {
            return true // Caller should retry the request
        }

        // Refresh failed, logout
        await logout()
        return false
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

            let (data, response) = try await URLSession.shared.data(for: request)

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

    private func scheduleRefresh() {
        refreshTask?.cancel()

        guard let token = accessToken else { return }
        guard let exp = jwtExpiration(token) else { return }

        // Refresh 60 seconds before expiry
        let refreshAt = exp.addingTimeInterval(-60)
        let delay = refreshAt.timeIntervalSinceNow

        guard delay > 0 else {
            // Already expired or about to expire, refresh now
            refreshTask = Task { @MainActor in
                _ = await tryRefresh()
            }
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            _ = await self?.tryRefresh()
        }
    }

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
