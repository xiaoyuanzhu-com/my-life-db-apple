//
//  NativeBridgeHandler.swift
//  MyLifeDB
//
//  WKScriptMessageHandler that receives messages from the web frontend
//  via window.webkit.messageHandlers.native.postMessage({ action, ... }).
//
//  Supported actions:
//  - share: Present native share sheet
//  - haptic: Trigger haptic feedback (iOS only)
//  - navigate: Sync web-side navigation to native tab state
//  - openExternal: Open URL in Safari
//  - copyToClipboard: Copy text to system clipboard
//  - log: Forward console messages to native log
//

import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class NativeBridgeHandler: NSObject, WKScriptMessageHandler {

    /// Callback when the web frontend navigates — native side should update tab selection.
    var onNavigate: ((String) -> Void)?

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            print("[NativeBridge] Invalid message format: \(message.body)")
            return
        }

        switch action {
        case "share":
            handleShare(body, webView: message.webView)
        case "haptic":
            handleHaptic(body)
        case "navigate":
            handleNavigate(body)
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

    private func handleShare(_ body: [String: Any], webView: WKWebView?) {
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

        Task { @MainActor in
            #if os(iOS)
            let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

            // Find the presenting view controller
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = scene.windows.first?.rootViewController else { return }

            // For iPad: set popover source
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = webView ?? rootVC.view
                popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootVC.present(activityVC, animated: true)
            #elseif os(macOS)
            guard let webView = webView else { return }
            let picker = NSSharingServicePicker(items: activityItems)
            picker.show(relativeTo: webView.bounds, of: webView, preferredEdge: .minY)
            #endif
        }
    }

    private func handleHaptic(_ body: [String: Any]) {
        #if os(iOS)
        let style = body["style"] as? String ?? "medium"
        Task { @MainActor in
            let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
            switch style {
            case "light": feedbackStyle = .light
            case "heavy": feedbackStyle = .heavy
            default: feedbackStyle = .medium
            }
            let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
            generator.impactOccurred()
        }
        #endif
    }

    private func handleNavigate(_ body: [String: Any]) {
        guard let path = body["path"] as? String else { return }
        Task { @MainActor in
            onNavigate?(path)
        }
    }

    private func handleOpenExternal(_ body: [String: Any]) {
        guard let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }

        Task { @MainActor in
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func handleCopyToClipboard(_ body: [String: Any]) {
        guard let text = body["text"] as? String else { return }

        Task { @MainActor in
            #if os(iOS)
            UIPasteboard.general.string = text
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
        }
    }

    private func handleLog(_ body: [String: Any]) {
        let level = body["level"] as? String ?? "log"
        let message = body["message"] as? String ?? "\(body)"
        print("[WebView:\(level)] \(message)")
    }
}
