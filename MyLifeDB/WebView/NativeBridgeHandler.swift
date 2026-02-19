//
//  NativeBridgeHandler.swift
//  MyLifeDB
//
//  URLSchemeHandler that receives messages from the web frontend
//  via fetch('nativebridge://message', { method: 'POST', body: JSON.stringify({ action, ... }) }).
//
//  Also provides a JavaScript polyfill so existing web code using
//  window.webkit.messageHandlers.native.postMessage({ action, ... })
//  continues to work unchanged.
//
//  Supported actions:
//  - share: Present native share sheet
//  - haptic: Trigger haptic feedback (iOS only)
//  - openExternal: Open URL in Safari
//  - copyToClipboard: Copy text to system clipboard
//  - log: Forward console messages to native log
//  - requestTokenRefresh: Await native token refresh (returns JSON response)
//

import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class NativeBridgeHandler: URLSchemeHandler {

    // MARK: - URLSchemeHandler

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        // Capture request data before entering the stream
        let body = request.httpBody
        let url = request.url ?? URL(string: "nativebridge://message")!

        return AsyncThrowingStream { continuation in
            guard let body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let action = json["action"] as? String else {
                print("[NativeBridge] Invalid message format from URL scheme request")
                let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
                continuation.yield(.response(response))
                continuation.finish()
                return
            }

            if action == "requestTokenRefresh" {
                // Async action: await native token refresh before responding
                Task { @MainActor in
                    let success = await AuthManager.shared.refreshAccessToken()
                    let responseBody = (try? JSONSerialization.data(
                        withJSONObject: ["success": success]
                    )) ?? Data("{}".utf8)
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    continuation.yield(.response(response))
                    continuation.yield(.data(responseBody))
                    continuation.finish()
                }
            } else {
                // Fire-and-forget for other actions
                Task { @MainActor in
                    self.dispatch(action: action, body: json)
                }
                let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil)!
                continuation.yield(.response(response))
                continuation.finish()
            }
        }
    }

    // MARK: - Dispatch

    @MainActor
    private func dispatch(action: String, body: [String: Any]) {
        switch action {
        case "share":
            handleShare(body)
        case "haptic":
            handleHaptic(body)
        case "openExternal":
            handleOpenExternal(body)
        case "copyToClipboard":
            handleCopyToClipboard(body)
        case "log":
            handleLog(body)
        default:
            print("[NativeBridge] Unknown action: \(action)")
        }
    }

    // MARK: - Action Handlers

    @MainActor
    private func handleShare(_ body: [String: Any]) {
        let title = body["title"] as? String ?? ""
        let url = body["url"] as? String
        let text = body["text"] as? String

        var activityItems: [Any] = []
        if !title.isEmpty { activityItems.append(title) }
        if let text = text, !text.isEmpty { activityItems.append(text) }
        if let urlString = url, let shareURL = URL(string: urlString) {
            activityItems.append(shareURL)
        }

        guard !activityItems.isEmpty else { return }
        presentShareSheet(items: activityItems)
    }

    @MainActor
    private func handleHaptic(_ body: [String: Any]) {
        #if os(iOS)
        let style = body["style"] as? String ?? "medium"
        let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case "light": feedbackStyle = .light
        case "heavy": feedbackStyle = .heavy
        default: feedbackStyle = .medium
        }
        let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
        generator.impactOccurred()
        #endif
    }

    @MainActor
    private func handleOpenExternal(_ body: [String: Any]) {
        guard let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }

        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    @MainActor
    private func handleCopyToClipboard(_ body: [String: Any]) {
        guard let text = body["text"] as? String else { return }

        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func handleLog(_ body: [String: Any]) {
        let level = body["level"] as? String ?? "log"
        let message = body["message"] as? String ?? "\(body)"
        print("[WebView:\(level)] \(message)")
    }

    // MARK: - JavaScript Polyfill

    /// Returns a JavaScript snippet that sets up the native bridge polyfill.
    /// This maps the old `window.webkit.messageHandlers.native.postMessage(msg)`
    /// API to the new `fetch('nativebridge://message', ...)` URL scheme approach,
    /// so existing web frontend code works without changes.
    static let bridgePolyfillScript: String = """
        window.isNativeApp = true;
        window.nativePlatform = '\(nativePlatform)';

        // Lock viewport to prevent zoom — keep viewport-fit=cover for safe-area insets.
        (function() {
            var meta = document.querySelector('meta[name="viewport"]');
            if (meta) {
                meta.content = 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
            }
        })();

        // Standalone auth re-check function — callable by native at any time,
        // independent of window.__nativeBridge (which is set up later by React).
        // Dispatches the same event that React's AuthProvider listens for.
        window.__nativeRecheckAuth = function() {
            window.dispatchEvent(new Event('native-recheck-auth'));
        };

        // Polyfill: map window.webkit.messageHandlers.native.postMessage → fetch
        if (!window.webkit) window.webkit = {};
        if (!window.webkit.messageHandlers) window.webkit.messageHandlers = {};
        window.webkit.messageHandlers.native = {
            postMessage: function(msg) {
                fetch('nativebridge://message', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(msg)
                }).catch(function() {});
            }
        };
        """

    private static var nativePlatform: String {
        #if os(iOS)
        "ios"
        #elseif os(macOS)
        "macos"
        #elseif os(visionOS)
        "visionos"
        #else
        "unknown"
        #endif
    }
}
