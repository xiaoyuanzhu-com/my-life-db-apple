//
//  APIClient.swift
//  MyLifeDB
//
//  Core API client using URLSession with async/await.
//  Single entry point for all network requests.
//

import Foundation

/// Main API client for communicating with MyLifeDB backend
final class APIClient {

    // MARK: - Singleton

    static let shared = APIClient()

    // MARK: - Configuration

    /// Base URL for the API server (reads from UserDefaults)
    var baseURL: URL {
        let urlString = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "https://my.xiaoyuanzhu.com"
        return URL(string: urlString) ?? URL(string: "https://my.xiaoyuanzhu.com")!
    }

    // MARK: - URLSession

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Endpoint Namespaces

    lazy var inbox = InboxAPI(client: self)
    lazy var library = LibraryAPI(client: self)
    lazy var search = SearchAPI(client: self)
    lazy var people = PeopleAPI(client: self)
    lazy var digest = DigestAPI(client: self)
    lazy var settings = SettingsAPI(client: self)

    // MARK: - Initialization

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60

        self.session = URLSession(configuration: configuration)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - HTTP Methods

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    // MARK: - Request Building

    /// Builds a URLRequest for the given endpoint
    func buildRequest(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth token if available
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    // MARK: - Generic Request Methods

    /// Performs a request and decodes the response
    func request<T: Decodable>(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil,
        allowRetryOn401: Bool = true
    ) async throws -> T {
        var bodyData: Data? = nil
        if let body = body {
            bodyData = try encoder.encode(body)
        }

        let request = try buildRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: bodyData
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle HTTP status codes
        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 400:
            throw APIError.badRequest(parseErrorMessage(from: data))
        case 401:
            // Try refresh and retry once
            if allowRetryOn401 {
                let refreshed = await AuthManager.shared.handleUnauthorized()
                if refreshed {
                    return try await self.request(
                        path: path, method: method, queryItems: queryItems,
                        body: body, allowRetryOn401: false
                    )
                }
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict(parseErrorMessage(from: data))
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode, parseErrorMessage(from: data))
        default:
            throw APIError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }

    /// Performs a request without expecting a decoded response body
    func requestVoid(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil,
        allowRetryOn401: Bool = true
    ) async throws {
        var bodyData: Data? = nil
        if let body = body {
            bodyData = try encoder.encode(body)
        }

        let request = try buildRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: bodyData
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 400:
            throw APIError.badRequest(parseErrorMessage(from: data))
        case 401:
            if allowRetryOn401 {
                let refreshed = await AuthManager.shared.handleUnauthorized()
                if refreshed {
                    try await self.requestVoid(
                        path: path, method: method, queryItems: queryItems,
                        body: body, allowRetryOn401: false
                    )
                    return
                }
            }
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict(parseErrorMessage(from: data))
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode, parseErrorMessage(from: data))
        default:
            throw APIError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }

    /// Performs a multipart form data upload
    func uploadMultipart<T: Decodable>(
        path: String,
        formFields: [String: String] = [:],
        files: [(name: String, filename: String, data: Data, mimeType: String)] = []
    ) async throws -> T {
        let boundary = UUID().uuidString

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Add form fields
        for (key, value) in formFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Add files
        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.serverError(httpResponse.statusCode, parseErrorMessage(from: data))
        }

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Raw File Access

    /// Gets raw file data from /raw/*path
    func getRawFile(path: String) async throws -> Data {
        let request = try buildRequest(path: "/raw/\(path)", method: .get)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                throw APIError.notFound
            }
            throw APIError.serverError(httpResponse.statusCode, nil)
        }

        return data
    }

    /// Saves raw file data to /raw/*path
    func saveRawFile(path: String, data: Data) async throws {
        var request = try buildRequest(path: "/raw/\(path)", method: .put)
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.serverError(httpResponse.statusCode, parseErrorMessage(from: responseData))
        }
    }

    /// Gets sqlar archive file from /sqlar/*path
    func getSqlarFile(path: String) async throws -> Data {
        let request = try buildRequest(path: "/sqlar/\(path)", method: .get)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                throw APIError.notFound
            }
            throw APIError.serverError(httpResponse.statusCode, nil)
        }

        return data
    }

    // MARK: - Helpers

    /// Parses error message from response body
    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: String?
            let message: String?
        }

        if let response = try? decoder.decode(ErrorResponse.self, from: data) {
            return response.error ?? response.message
        }
        return nil
    }
}

// MARK: - URL Building Helpers

extension APIClient {

    /// Builds a URL for raw file access
    func rawFileURL(path: String) -> URL {
        baseURL.appendingPathComponent("raw").appendingPathComponent(path)
    }

    /// Builds a URL for sqlar file access
    func sqlarFileURL(path: String) -> URL {
        baseURL.appendingPathComponent("sqlar").appendingPathComponent(path)
    }
}
