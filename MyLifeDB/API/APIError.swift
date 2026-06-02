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

    /// Failed to decode response. Carries diagnostic context (endpoint,
    /// status, body snippet, underlying DecodingError) so a parse failure
    /// names the exact endpoint and shape mismatch.
    case decodingError(DecodingFailure)

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
        case .decodingError(let failure):
            return "Failed to parse \(failure.path) [HTTP \(failure.statusCode)]: \(failure.detail)\nBody: \(failure.bodySnippet)"
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

/// Diagnostic context captured when a 2xx response body fails to decode.
/// Turns iOS's opaque "data isn't in the correct format" into something
/// actionable: which endpoint, what status, the exact DecodingError, and a
/// snippet of the body that failed to parse.
struct DecodingFailure: Error {
    let path: String
    let statusCode: Int
    let bodySnippet: String
    let underlying: Error

    /// Coding path + reason pulled out of the underlying DecodingError.
    /// Distinguishes "body isn't JSON" (dataCorrupted at root) from a
    /// per-field type/shape mismatch.
    var detail: String {
        guard let decodingError = underlying as? DecodingError else {
            return underlying.localizedDescription
        }
        switch decodingError {
        case .dataCorrupted(let ctx):
            return "dataCorrupted at [\(Self.codingPath(ctx))]: \(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            return "keyNotFound '\(key.stringValue)' at [\(Self.codingPath(ctx))]: \(ctx.debugDescription)"
        case .typeMismatch(let type, let ctx):
            return "typeMismatch (expected \(type)) at [\(Self.codingPath(ctx))]: \(ctx.debugDescription)"
        case .valueNotFound(let type, let ctx):
            return "valueNotFound (\(type)) at [\(Self.codingPath(ctx))]: \(ctx.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    /// One-line form for Console logging.
    var logLine: String {
        "\(path) [HTTP \(statusCode)] \(detail) | body: \(bodySnippet)"
    }

    private static func codingPath(_ ctx: DecodingError.Context) -> String {
        let joined = ctx.codingPath.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "<root>" : joined
    }

    /// First `limit` chars of the body as UTF-8 (or a byte-count placeholder
    /// for binary). Whitespace-trimmed so an HTML/empty body is obvious.
    static func snippet(from data: Data, limit: Int = 300) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes, non-UTF8>"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "<empty, \(data.count) bytes>"
        }
        if trimmed.count > limit {
            return String(trimmed.prefix(limit)) + "…(\(trimmed.count) chars total)"
        }
        return trimmed
    }
}
