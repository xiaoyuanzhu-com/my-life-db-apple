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

    /// Ensures the SSE connection is active.  If it was previously stopped
    /// (e.g. the app went to background and the OS tore down the socket),
    /// this will tear down the stale connection and reconnect with a fresh
    /// auth token.  Safe to call repeatedly — no-ops when already connected.
    func ensureRunning() {
        if isRunning { return }
        // Full restart: tear down any leftover state, then reconnect
        stop()
        start()
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

        // The backend sends unnamed SSE events — the event type lives inside
        // the JSON payload as `"type"`, NOT in an SSE `event:` header.
        // Format:  data: {"type":"claude-session-updated",...}\n\n
        //
        // This matches how the web frontend parses events (onmessage → JSON.parse → data.type).
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            handleEventJSON(json)
        }
    }

    private func handleEventJSON(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        // Ignore connection confirmation (same as web: `if (data.type === 'connected') return`)
        guard type != "connected" else { return }

        DispatchQueue.main.async { [weak self] in
            switch type {
            case "claude-session-updated":
                self?.onSessionUpdated?()
            default:
                break
            }
        }
    }

    fileprivate func handleDisconnect(authFailed: Bool = false) {
        guard isRunning else { return }

        // Reconnect with backoff
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30) // Cap at 30s

        Task { @MainActor [weak self] in
            // Attempt token refresh before reconnecting (required per auth doc).
            // Without this, SSE reconnects with the same expired token forever.
            if authFailed {
                _ = await AuthManager.shared.refreshAccessToken()
            }

            guard let self, self.isRunning else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.connect()
            }
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
            // triggers reconnect with proper backoff + token refresh.
            lastResponseWas401 = true
            completionHandler(.cancel)
            return
        }
        lastResponseWas401 = false
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
        manager?.handleDisconnect(authFailed: lastResponseWas401)
        lastResponseWas401 = false
    }

    /// Tracks whether the last response was a 401 so handleDisconnect
    /// knows to attempt a token refresh before reconnecting.
    private var lastResponseWas401 = false
}
