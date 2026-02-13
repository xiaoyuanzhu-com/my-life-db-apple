//
//  SharedConstants.swift
//  Shared between MyLifeDB app and Share Extension
//
//  Single source of truth for constants that both the main app
//  and the Share Extension need to access.
//

import Foundation

enum SharedConstants {

    /// App Group identifier for sharing data between app and extensions.
    static let appGroupID = "group.xiaoyuanzhu.MyLifeDB"

    /// Keychain service name (must match KeychainHelper.service in main app).
    static let keychainService = "com.mylifedb.auth"

    /// Keychain key for the access token (must match AuthManager.accessTokenKey).
    static let accessTokenKey = "mylifedb.accessToken"

    /// UserDefaults key for the API base URL.
    static let apiBaseURLKey = "apiBaseURL"

    /// Default backend URL.
    static let defaultBaseURL = "https://my.xiaoyuanzhu.com"

    /// UserDefaults suite shared between app and extension via App Group.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// Reads the configured API base URL from shared UserDefaults.
    static var apiBaseURL: URL {
        let urlString = sharedDefaults.string(forKey: apiBaseURLKey) ?? defaultBaseURL
        return URL(string: urlString) ?? URL(string: defaultBaseURL)!
    }
}
