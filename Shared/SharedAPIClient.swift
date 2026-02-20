//
//  SharedAPIClient.swift
//  Shared between MyLifeDB app and Share Extension
//
//  Lightweight API client for uploading content to the Inbox.
//  Does not depend on AuthManager or APIClient singletons,
//  so it can run safely in the Share Extension's process.
//

import Foundation

// MARK: - Error Types

enum ShareUploadError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case uploadFailed(Int, String?)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not signed in. Please open MyLifeDB and sign in first."
        case .invalidURL:
            return "Invalid server URL."
        case .uploadFailed(let code, let message):
            return message ?? "Upload failed (HTTP \(code))."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Response Model

/// Per-file result in an upload response
struct ShareUploadFileResult: Codable {
    let path: String
    let status: String  // "created" or "skipped"
}

/// Response from POST /api/inbox
/// (Matches CreateInboxResponse in InboxItem.swift in the main app)
struct ShareCreateInboxResponse: Codable {
    let path: String
    let paths: [String]
    let results: [ShareUploadFileResult]?  // nil for older server versions
}

// MARK: - API Client

struct SharedAPIClient {

    /// Upload text and/or files to the inbox.
    ///
    /// - Parameters:
    ///   - text: Optional markdown text content
    ///   - files: Array of files with filename, data, and MIME type
    /// - Returns: The server response with created paths
    @discardableResult
    func uploadToInbox(
        text: String?,
        files: [(filename: String, data: Data, mimeType: String)]
    ) async throws -> ShareCreateInboxResponse {
        guard let token = SharedKeychainHelper.loadAccessToken() else {
            throw ShareUploadError.notAuthenticated
        }

        let baseURL = SharedConstants.apiBaseURL
        let url = baseURL.appendingPathComponent("api/inbox")

        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        var body = Data()

        // Add text field
        if let text = text, !text.isEmpty {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"text\"\r\n\r\n")
            body.appendString("\(text)\r\n")
        }

        // Add files
        for file in files {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"files\"; filename=\"\(file.filename)\"\r\n")
            body.appendString("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ShareUploadError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareUploadError.uploadFailed(0, "Invalid response")
        }

        guard 200...299 ~= httpResponse.statusCode else {
            let message = parseErrorMessage(from: data)
            if httpResponse.statusCode == 401 {
                throw ShareUploadError.notAuthenticated
            }
            throw ShareUploadError.uploadFailed(httpResponse.statusCode, message)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ShareCreateInboxResponse.self, from: data)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: String?
            let message: String?
        }
        if let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return response.error ?? response.message
        }
        return nil
    }
}

// MARK: - Data Helper

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
