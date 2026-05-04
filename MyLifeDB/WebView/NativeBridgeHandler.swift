//
//  NativeBridgeHandler.swift
//  MyLifeDB
//
//  WKScriptMessageHandlerWithReply that receives messages from the web frontend
//  via window.webkit.messageHandlers.native.postMessage({ action, ... }).
//
//  Why not URLSchemeHandler? Custom URL schemes (e.g. nativebridge://) are
//  treated as insecure by WebKit's mixed-content blocker, so fetch() calls to
//  them from HTTPS pages are rejected before reaching the handler. Script
//  message handlers travel over WebKit's IPC channel and are unaffected.
//
//  Supported actions:
//  - share: Present native share sheet (no reply)
//  - haptic: Trigger haptic feedback, iOS only (no reply)
//  - openExternal: Open URL in Safari (no reply)
//  - copyToClipboard: Copy text to system clipboard (no reply)
//  - log: Forward console messages to native log (no reply)
//  - fullscreenPreview: Toggle fullscreen preview state (no reply)
//  - navigate: Navigate to a route in the native app (no reply)
//  - goBack: Request back navigation in the host NavigationStack (no reply)
//  - pickAndUploadFiles: Present document picker, upload picked files,
//      reply with { attachments: [...] } (iOS only; macOS replies with [])
//  - requestTokenRefresh: Await native token refresh,
//      reply with { success: Bool, accessToken?: String }
//

import WebKit
import Observation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
final class NativeBridgeHandler: NSObject, WKScriptMessageHandlerWithReply {

    // MARK: - Observable State

    /// Whether the web frontend is showing a fullscreen preview (e.g. Estima slides).
    /// When true, the hosting view should disable the NavigationStack's interactive
    /// pop gesture so swipe gestures reach the iframe content instead.
    private(set) var isFullscreenPreview = false

    /// Set to true when the web frontend requests a back navigation (e.g. edge swipe).
    /// The hosting SwiftUI view should observe this and call dismiss().
    private(set) var isRequestingGoBack = false

    #if os(iOS)
    /// Retains the active document picker delegate while a `pickAndUploadFiles`
    /// session is in flight. UIDocumentPickerViewController.delegate is `weak`,
    /// so the coordinator must be held by us until it fires its callback.
    /// Cleared in the coordinator's completion. Only one picker is presentable
    /// at a time on iOS, so a single slot is sufficient.
    @ObservationIgnored
    var activeFilePickerCoordinator: FilePickerCoordinator?
    #endif

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            replyHandler(nil, "Invalid message format: expected { action: ... }")
            return
        }

        switch action {
        case "pickAndUploadFiles":
            #if os(iOS)
            Task { @MainActor [weak self] in
                guard let self else {
                    replyHandler(["attachments": []], nil)
                    return
                }
                let storageId = body["storageId"] as? String
                let result = await self.handlePickAndUploadFiles(storageId: storageId)
                replyHandler(result, nil)
            }
            #else
            replyHandler(["attachments": []], nil)
            #endif

        case "requestTokenRefresh":
            Task { @MainActor in
                let success = await AuthManager.shared.refreshAccessToken()
                var result: [String: Any] = ["success": success]
                if success, let token = AuthManager.shared.accessToken {
                    result["accessToken"] = token
                }
                replyHandler(result, nil)
            }

        default:
            // Fire-and-forget — dispatch and reply immediately with nil.
            Task { @MainActor [weak self] in
                self?.dispatch(action: action, body: body)
            }
            replyHandler(nil, nil)
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

    /// Returns a JavaScript snippet that sets up native-app feature flags and
    /// viewport hardening. The actual `webkit.messageHandlers.native` object
    /// is registered natively via WKUserContentController.addScriptMessageHandler,
    /// so this script must NOT redefine it.
    static let bridgePolyfillScript: String = """
        window.isNativeApp = true;
        window.nativePlatform = '\(nativePlatform)';

        // Lock viewport to prevent zoom — keep viewport-fit=cover for safe-area insets.
        // Two layers of defense:
        //   1. Viewport meta: create-or-update with user-scalable=no
        //   2. JS gesture prevention: block pinch/double-tap zoom at the event level
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
