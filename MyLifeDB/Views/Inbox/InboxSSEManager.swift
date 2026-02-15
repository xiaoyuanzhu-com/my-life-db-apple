//
//  InboxSSEManager.swift
//  MyLifeDB
//
//  Server-Sent Events manager for inbox real-time updates.
//  Connects to GET /api/notifications/stream and listens for
//  inbox-changed and pin-changed events.
//

import Foundation

@Observable
final class InboxSSEManager {

    var onInboxChanged: (() -> Void)?
    var onPinChanged: (() -> Void)?

    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var isRunning = false
    private var reconnectDelay: TimeInterval = 1

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reconnectDelay = 1
        connect()
    }

    func stop() {
        isRunning = false
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func connect() {
        guard isRunning else { return }

        let baseURL = AuthManager.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/notifications/stream") else {
            print("[SSE] Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval.infinity

        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = SSESessionDelegate(manager: self)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        task = session?.dataTask(with: request)
        task?.resume()
    }

    fileprivate func handleData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        // Parse SSE format: lines separated by \n
        // event: <name>\ndata: <json>\n\n
        let lines = text.components(separatedBy: "\n")
        var currentEvent: String?

        for line in lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                let eventName = currentEvent ?? "message"
                handleEvent(name: eventName)
                currentEvent = nil
            } else if line.isEmpty {
                currentEvent = nil
            }
        }
    }

    private func handleEvent(name: String) {
        DispatchQueue.main.async { [weak self] in
            switch name {
            case "inbox-changed":
                self?.onInboxChanged?()
            case "pin-changed":
                self?.onPinChanged?()
            default:
                break
            }
        }
    }

    fileprivate func handleDisconnect() {
        guard isRunning else { return }

        // Reconnect with backoff
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30) // Cap at 30s

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    fileprivate func handleConnected() {
        reconnectDelay = 1 // Reset on successful connection
    }
}

// MARK: - URLSession Delegate

private class SSESessionDelegate: NSObject, URLSessionDataDelegate {
    weak var manager: InboxSSEManager?

    init(manager: InboxSSEManager) {
        self.manager = manager
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        manager?.handleData(data)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        manager?.handleConnected()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? NSError, error.code == NSURLErrorCancelled {
            return // Intentional cancellation
        }
        manager?.handleDisconnect()
    }
}
