//
//  UploadProgressDelegate.swift
//  MyLifeDB
//
//  Per-task URLSessionTaskDelegate that forwards
//  didSendBodyData callbacks to a closure as a fractional progress value.
//
//  Used by APIClient.uploadRawFromFile to surface upload progress to the
//  share-extension drain UI.
//

import Foundation

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend totalBytesExpected: Int64
    ) {
        guard totalBytesExpected > 0 else { return }
        let p = max(0, min(1, Double(totalBytesSent) / Double(totalBytesExpected)))
        let cb = onProgress
        Task { @MainActor in cb(p) }
    }
}
