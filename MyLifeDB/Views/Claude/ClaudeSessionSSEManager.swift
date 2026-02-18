//
//  ClaudeSessionSSEManager.swift
//  MyLifeDB
//
//  Server-Sent Events manager for Claude session real-time updates.
//  Connects to GET /api/notifications/stream and listens for
//  claude-session-updated events to trigger session list refreshes.
//

import Foundation

@Observable
final class ClaudeSessionSSEManager {

    var onSessionUpdated: (() -> Void)?

    private var task: URLSessionDataTask?
    private var session: URLSession?
    fileprivate var isRunning = false
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
            print("[ClaudeSSE] Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = TimeInterval.infinity

        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = ClaudeSSESessionDelegate(manager: self)
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
            case "claude-session-updated":
                self?.onSessionUpdated?()
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

private class ClaudeSSESessionDelegate: NSObject, URLSessionDataDelegate {
    weak var manager: ClaudeSessionSSEManager?

    init(manager: ClaudeSessionSSEManager) {
        self.manager = manager
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        manager?.handleData(data)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // Don't reset backoff on auth failure — cancel so didCompleteWithError
            // triggers reconnect with proper backoff.
            completionHandler(.cancel)
            return
        }
        manager?.handleConnected()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // .cancel from didReceive arrives as NSURLErrorCancelled — but only
        // treat it as intentional if the manager itself called stop().
        if let error = error as? NSError, error.code == NSURLErrorCancelled,
           manager?.isRunning != true {
            return // Intentional cancellation via stop()
        }
        manager?.handleDisconnect()
    }
}
