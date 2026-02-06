//
//  OAuthHelper.swift
//  MyLifeDB
//
//  Helper to open OAuth login in the system default browser
//  and parse callback URLs from the mylifedb:// URL scheme.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum OAuthHelper {

    /// Opens the OAuth authorize URL in the system default browser.
    /// The browser will complete the OAuth flow and redirect back via mylifedb:// scheme.
    static func openLoginInBrowser(baseURL: URL) {
        let callbackScheme = "mylifedb"
        let nativeRedirect = "\(callbackScheme)://oauth/callback"
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/oauth/authorize"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "native_redirect", value: nativeRedirect)
        ]

        guard let authorizeURL = components?.url else { return }

        #if canImport(UIKit)
        UIApplication.shared.open(authorizeURL)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(authorizeURL)
        #endif
    }

    /// Parses an incoming OAuth callback URL (mylifedb://oauth/callback?access_token=...&refresh_token=...)
    /// Returns (accessToken, refreshToken?) or nil if the URL isn't a valid callback.
    static func parseCallbackURL(_ url: URL) -> (accessToken: String, refreshToken: String?)? {
        guard url.scheme == "mylifedb",
              url.host == "oauth",
              url.path == "/callback" || url.path == "callback" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []

        guard let accessToken = queryItems.first(where: { $0.name == "access_token" })?.value,
              !accessToken.isEmpty else {
            return nil
        }

        let refreshToken = queryItems.first(where: { $0.name == "refresh_token" })?.value

        return (accessToken, refreshToken)
    }
}
