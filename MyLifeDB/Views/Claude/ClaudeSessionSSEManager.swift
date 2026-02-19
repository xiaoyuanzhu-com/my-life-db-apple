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

    /// Buffer for incoming SSE data.  Network chunks can split mid-event
    /// (e.g. the `data:` line arrives in one chunk and the trailing `\n\n`
    /// in the next).  We accumulate bytes here and only process complete
    /// events — those terminated by a blank line (`\n\n`).
    fileprivate var buffer = ""

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

    /// Ensures the SSE connection is active.  Always tears down any existing
    /// connection and reconnects with a fresh auth token.  This handles the
    /// case where iOS killed the network socket while the app was in the
    /// background but `isRunning` stayed true (no delegate callback fired).
    func ensureRunning() {
        stop()
        start()
    }

    private func connect() {
        guard isRunning else { return }

        // Invalidate any existing session before creating a new one.
        // URLSession retains its delegate strongly — without this, each
        // reconnect leaks the previous session and its network resources.
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil

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

        buffer = "" // Reset buffer for new connection

        let delegate = ClaudeSSESessionDelegate(manager: self)
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        task = session?.dataTask(with: request)
        task?.resume()
    }

    /// Appends raw network bytes to the buffer and processes any complete
    /// SSE events.  Per the SSE spec, events are delimited by a blank line
    /// (`\n\n`).  Partial data stays in the buffer until the next chunk
    /// completes it.
    ///
    /// The backend sends unnamed events — the event type lives inside the
    /// JSON payload as `"type"`, NOT in an SSE `event:` header.
    /// Format:  `data: {"type":"claude-session-updated",...}\n\n`
    ///
    /// This matches how the web frontend parses events
    /// (`EventSource.onmessage` → `JSON.parse` → `data.type`).
    fileprivate func handleData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer.append(text)

        // Split on the SSE event delimiter (\n\n).  Complete events are all
        // segments except the last, which may be a partial event still
        // accumulating.
        var segments = buffer.components(separatedBy: "\n\n")
        buffer = segments.removeLast() // Keep incomplete tail in buffer

        for event in segments {
            for line in event.components(separatedBy: "\n") {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))
                handleEventJSON(json)
            }
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
