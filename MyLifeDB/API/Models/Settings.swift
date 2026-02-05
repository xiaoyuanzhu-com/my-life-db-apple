//
//  Settings.swift
//  MyLifeDB
//
//  Settings models for app configuration.
//

import Foundation

/// Application settings
struct AppSettings: Codable {
    // Add settings properties as needed from your backend
    // This is a placeholder - update based on your actual settings schema

    var theme: String?
    var language: String?

    // Add more settings as defined in your backend
}

/// Response from GET /api/settings
struct SettingsResponse: Codable {
    // Match your backend settings response
    // Placeholder - customize based on your actual schema
}

/// Request body for PUT /api/settings
struct UpdateSettingsRequest: Codable {
    // Match your backend settings request
    // Placeholder - customize based on your actual schema
}
