//
//  APIError.swift
//  MyLifeDB
//
//  API error types for handling network errors.
//

import Foundation

/// Errors that can occur during API requests
enum APIError: LocalizedError {

    // MARK: - Client Errors

    /// The URL could not be constructed
    case invalidURL

    /// The response was not a valid HTTP response
    case invalidResponse

    /// Request was malformed (400)
    case badRequest(String?)

    /// Authentication required (401)
    case unauthorized

    /// Access denied (403)
    case forbidden

    /// Resource not found (404)
    case notFound

    /// Resource conflict (409)
    case conflict(String?)

    /// Backend instance is being provisioned (503 with provisioning flag)
    case provisioning

    // MARK: - Server Errors

    /// Server error with status code
    case serverError(Int, String?)

    /// Unexpected status code
    case unexpectedStatusCode(Int)

    // MARK: - Parsing Errors

    /// Failed to decode response
    case decodingError(Error)

    /// Failed to encode request body
    case encodingError(Error)

    // MARK: - Network Errors

    /// Network request failed
    case networkError(Error)

    /// Request timed out
    case timeout

    /// No network connection
    case noConnection

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid URL")
        case .invalidResponse:
            return String(localized: "Invalid server response")
        case .badRequest(let message):
            return message ?? String(localized: "Bad request")
        case .unauthorized:
            return String(localized: "Authentication required")
        case .forbidden:
            return String(localized: "Access denied")
        case .notFound:
            return String(localized: "Resource not found")
        case .conflict(let message):
            return message ?? String(localized: "Resource conflict")
        case .provisioning:
            return String(localized: "Setting up your space")
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))"
        case .unexpectedStatusCode(let code):
            return "Unexpected response (\(code))"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return String(localized: "Request timed out")
        case .noConnection:
            return String(localized: "No network connection")
        }
    }

    /// Whether this error is recoverable by retrying
    var isRetryable: Bool {
        switch self {
        case .serverError(let code, _):
            return code >= 500
        case .timeout, .noConnection, .networkError:
            return true
        default:
            return false
        }
    }

    /// User-friendly message for display
    var userMessage: String {
        switch self {
        case .unauthorized:
            return String(localized: "Please log in to continue.")
        case .forbidden:
            return String(localized: "You don't have permission to access this.")
        case .notFound:
            return String(localized: "The requested item was not found.")
        case .noConnection:
            return String(localized: "No internet connection. Please check your network.")
        case .timeout:
            return String(localized: "The request timed out. Please try again.")
        case .provisioning:
            return String(localized: "Setting up your space. This may take a moment.")
        case .serverError:
            return String(localized: "Server error. Please try again later.")
        default:
            return errorDescription ?? "An error occurred."
        }
    }
}
