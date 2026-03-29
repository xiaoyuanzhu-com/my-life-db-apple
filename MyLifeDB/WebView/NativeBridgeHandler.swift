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
//  - fullscreenPreview: Toggle fullscreen preview state (disables swipe-back)
//  - navigate: Navigate to a route in the native app (switches tabs)
//

import WebKit
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
final class NativeBridgeHandler: URLSchemeHandler {

    // MARK: - Observable State

    /// Whether the web frontend is showing a fullscreen preview (e.g. Estima slides).
    /// When true, the hosting view should disable the NavigationStack's interactive
    /// pop gesture so swipe gestures reach the iframe content instead.
    private(set) var isFullscreenPreview = false

    /// Set to true when the web frontend requests a back navigation (e.g. edge swipe).
    /// The hosting SwiftUI view should observe this and call dismiss().
    private(set) var isRequestingGoBack = false

    // MARK: - URLSchemeHandler

    // CORS headers required because the WebView's page origin (e.g. http://192.168.x.x:12346)
    // differs from the nativebridge:// scheme, triggering cross-origin enforcement in WebKit.
    private static let corsHeaders: [String: String] = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    ]

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        // Capture request data before entering the stream
        let body = request.httpBody
        let url = request.url ?? URL(string: "nativebridge://message")!
        let method = request.httpMethod ?? "POST"

        return AsyncThrowingStream { continuation in
            // Handle CORS preflight
            if method == "OPTIONS" {
                let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: Self.corsHeaders)!
                continuation.yield(.response(response))
                continuation.finish()
                return
            }

            guard let body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let action = json["action"] as? String else {
                print("[NativeBridge] Invalid message format from URL scheme request")
                let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: Self.corsHeaders)!
                continuation.yield(.response(response))
                continuation.finish()
                return
            }

            if action == "requestTokenRefresh" {
                // Async action: await native token refresh before responding.
                // Include the new access token so the web side can update its
                // Authorization header immediately (before the async notification).
                Task { @MainActor in
                    let success = await AuthManager.shared.refreshAccessToken()
                    var result: [String: Any] = ["success": success]
                    if success, let token = AuthManager.shared.accessToken {
                        result["accessToken"] = token
                    }
                    let responseBody = (try? JSONSerialization.data(
                        withJSONObject: result
                    )) ?? Data("{}".utf8)
                    var headers = Self.corsHeaders
                    headers["Content-Type"] = "application/json"
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: headers
                    )!
                    continuation.yield(.response(response))
                    continuation.yield(.data(responseBody))
                    continuation.finish()
                }
            } else {
                // Fire-and-forget for other actions
                Task { @MainActor [weak self] in
                    self?.dispatch(action: action, body: json)
                }
                let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: Self.corsHeaders)!
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
        case "fullscreenPreview":
            handleFullscreenPreview(body)
        case "navigate":
            handleNavigate(body)
        case "goBack":
            isRequestingGoBack = true
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

    @MainActor
    private func handleFullscreenPreview(_ body: [String: Any]) {
        isFullscreenPreview = (body["isFullscreen"] as? Bool) ?? false
    }

    @MainActor
    private func handleNavigate(_ body: [String: Any]) {
        guard let path = body["path"] as? String else { return }
        NotificationCenter.default.post(
            name: .nativeNavigateRequest,
            object: nil,
            userInfo: ["path": path]
        )
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
        // Three layers of defense:
        //   1. Native: .webViewAllowsMagnification(false) on the SwiftUI WebView (primary)
        //   2. Viewport meta: create-or-update with user-scalable=no (belt-and-suspenders)
        //   3. JS gesture prevention: block pinch/double-tap zoom at the event level
        // Also disable WebKit text auto-sizing which can cause apparent zoom changes
        // during dynamic content updates (e.g. streaming messages).
        (function() {
            var viewportContent = 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';

            // At document-start the <head> may not be parsed yet, so create the
            // meta tag immediately (it will be the first element in <head>).
            // If the HTML later declares its own viewport meta, we update it via
            // a DOMContentLoaded listener below.
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = viewportContent;
            document.documentElement.appendChild(meta);

            // Once the DOM is fully parsed, ensure the viewport meta is correct
            // (the HTML's own <meta viewport> may have overwritten ours).
            document.addEventListener('DOMContentLoaded', function() {
                var tags = document.querySelectorAll('meta[name="viewport"]');
                // Keep only one, with our locked content
                for (var i = 0; i < tags.length; i++) {
                    if (i === 0) {
                        tags[i].content = viewportContent;
                    } else {
                        tags[i].remove();
                    }
                }
            });

            document.documentElement.style.webkitTextSizeAdjust = '100%';

            // CSS touch-action: disable pinch-zoom and double-tap-zoom at the
            // rendering level. 'manipulation' allows pan + tap but blocks zoom.
            document.documentElement.style.touchAction = 'manipulation';

            // Block Safari/WebKit gesture events (pinch-to-zoom).
            document.addEventListener('gesturestart', function(e) { e.preventDefault(); }, { passive: false, capture: true });
            document.addEventListener('gesturechange', function(e) { e.preventDefault(); }, { passive: false, capture: true });
            document.addEventListener('gestureend', function(e) { e.preventDefault(); }, { passive: false, capture: true });
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

        // Open target="_blank" links (external URLs) in Safari instead of the WebView.
        // WebPage doesn't expose WKUIDelegate's createWebViewWith, so target="_blank"
        // links would silently do nothing without this handler.
        document.addEventListener('click', function(e) {
            var a = e.target.closest('a[target="_blank"]');
            if (!a) return;
            var href = a.href;
            if (href && /^https?:\\/\\//.test(href)) {
                e.preventDefault();
                window.webkit.messageHandlers.native.postMessage({ action: 'openExternal', url: href });
            }
        }, true);
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
