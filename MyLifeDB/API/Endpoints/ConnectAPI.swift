//
//  ConnectAPI.swift
//  MyLifeDB
//
//  Third-party OAuth Connect endpoints. Backend hosts the consent flow;
//  the iOS client renders a native consent UI and posts the user's
//  decision back, then bounces to the third-party app's custom URL
//  scheme using the `redirectTo` URL returned by the server.
//
//  Endpoints:
//  - GET  /api/connect/authorize/preview  - Validate params, get client/scopes
//  - POST /api/connect/consent            - Submit approve/deny
//

import Foundation

/// API endpoints for the Connect (third-party OAuth) flow.
struct ConnectAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Preview

    /// Validate OAuth params server-side and resolve the client + scope metadata.
    /// The same call upserts the client row, so the user never sees an unknown client.
    func preview(params: [String: String]) async throws -> ConnectPreviewResponse {
        let queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await client.request(
            path: "/api/connect/authorize/preview",
            queryItems: queryItems,
            ignoreCache: true
        )
    }

    // MARK: - Consent

    /// Submit the user's approve/deny decision. Returns the `redirectTo` URL
    /// to send the user back to the third-party app.
    func consent(params: [String: String], approve: Bool) async throws -> ConnectConsentResponse {
        var body: [String: ConsentValue] = [:]
        for (k, v) in params {
            body[k] = .string(v)
        }
        body["approve"] = .bool(approve)
        return try await client.request(
            path: "/api/connect/consent",
            method: .post,
            body: body
        )
    }
}

// MARK: - Models

/// Wrapper for mixed-type JSON body values (strings + bool).
enum ConsentValue: Encodable {
    case string(String)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .bool(let b): try container.encode(b)
        }
    }
}

/// Response from GET /api/connect/authorize/preview
struct ConnectPreviewResponse: Decodable {
    let data: PreviewData

    struct PreviewData: Decodable {
        let client: Client
        let requestedMethods: [Method]
        let grantedMethods: [Method]
        let newMethods: [Method]
        let canSilentApprove: Bool
        let redirectUri: String
    }

    struct Client: Decodable {
        let id: String
        let name: String
        let iconUrl: String
        let verified: Bool
    }

    /// A capability the app is asking for. Server provides the human-readable
    /// `label` so the consent screen doesn't have to map names locally.
    struct Method: Decodable, Hashable {
        let name: String
        let label: String
    }
}

/// Response from POST /api/connect/consent
struct ConnectConsentResponse: Decodable {
    let data: ConsentData

    struct ConsentData: Decodable {
        let redirectTo: String
    }
}
