//
//  SharedKeychainHelper.swift
//  Shared between MyLifeDB app and Share Extension
//
//  Read-only keychain access for the Share Extension.
//  Mirrors the query pattern in KeychainHelper.swift (main app)
//  to ensure the same keychain items are accessed.
//

import Foundation
import Security

enum SharedKeychainHelper {

    /// Load the access token from the shared Keychain group.
    ///
    /// Both the main app and extension share the same keychain-access-group
    /// `$(AppIdentifierPrefix)com.mylifedb.auth`, so items saved by the main
    /// app's `KeychainHelper.save()` are readable here without code changes.
    static func loadAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedConstants.keychainService,
            kSecAttrAccount as String: SharedConstants.accessTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
