//
//  SharedAPIClient.swift
//  Shared between MyLifeDB app and Share Extension
//
//  Lightweight API client for uploading shared content into the
//  user's library. Does not depend on AuthManager or APIClient
//  singletons, so it can run safely in the Share Extension's process.
//
//  Uses the backend's simple upload endpoint:
//    PUT /api/data/uploads/simple/<destination>/<filename>
//  with the raw file bytes as the request body and the MIME type
//  in the Content-Type header. Each file is uploaded as a separate
//  request; a user note (if any) is uploaded as an extra .md file.
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

/// Per-file result in a simple-upload response
struct ShareUploadFileResult: Codable {
    let path: String
    let status: String  // "created" or "skipped"
}

/// Response from PUT /api/data/uploads/simple/*path
struct ShareSimpleUploadResponse: Codable {
    let success: Bool?
    let path: String
    let paths: [String]?
    let results: [ShareUploadFileResult]?
}

// MARK: - API Client

struct SharedAPIClient {

    /// Destination folder for shared content. Files land here and the
    /// backend's normal library-changed notifications fire.
    private static let destination = "inbox"

    /// Upload text and/or files into the user's library.
    ///
    /// Each file (and the text note, if non-empty) is uploaded via a
    /// separate `PUT /api/data/uploads/simple/<destination>/<filename>` call.
    ///
    /// - Parameters:
    ///   - text: Optional markdown text content. Uploaded as a `.md` file.
    ///   - files: Array of files with filename, data, and MIME type.
    /// - Returns: The combined results from all uploads.
    @discardableResult
    func upload(
        text: String?,
        files: [(filename: String, data: Data, mimeType: String)]
    ) async throws -> [ShareUploadFileResult] {
        guard let token = SharedKeychainHelper.loadAccessToken() else {
            throw ShareUploadError.notAuthenticated
        }

        var results: [ShareUploadFileResult] = []

        // Upload each file
        for file in files {
            let r = try await putSimple(
                token: token,
                filename: file.filename,
                data: file.data,
                mimeType: file.mimeType
            )
            results.append(contentsOf: r)
        }

        // Upload the user note as a markdown file (if present)
        if let text = text, !text.isEmpty {
            let noteFilename = makeNoteFilename()
            if let data = text.data(using: .utf8) {
                let r = try await putSimple(
                    token: token,
                    filename: noteFilename,
                    data: data,
                    mimeType: "text/markdown"
                )
                results.append(contentsOf: r)
            }
        }

        return results
    }

    // MARK: - Single Simple Upload

    private func putSimple(
        token: String,
        filename: String,
        data: Data,
        mimeType: String
    ) async throws -> [ShareUploadFileResult] {
        let baseURL = SharedConstants.apiBaseURL
        // Path: /api/data/uploads/simple/<destination>/<filename>
        // Note: appendingPathComponent percent-encodes each segment.
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("data")
            .appendingPathComponent("uploads")
            .appendingPathComponent("simple")
            .appendingPathComponent(Self.destination)
            .appendingPathComponent(filename)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = data

        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ShareUploadError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareUploadError.uploadFailed(0, "Invalid response")
        }

        guard 200...299 ~= httpResponse.statusCode else {
            let message = parseErrorMessage(from: responseData)
            if httpResponse.statusCode == 401 {
                throw ShareUploadError.notAuthenticated
            }
            throw ShareUploadError.uploadFailed(httpResponse.statusCode, message)
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ShareSimpleUploadResponse.self, from: responseData)
        return decoded.results ?? [ShareUploadFileResult(path: decoded.path, status: "created")]
    }

    // MARK: - Helpers

    /// Build a timestamped filename for a free-form note: e.g. `note-2026-05-01-143052.md`.
    /// Using a timestamp avoids collisions when the user shares notes back-to-back.
    private func makeNoteFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "note-\(formatter.string(from: Date())).md"
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
