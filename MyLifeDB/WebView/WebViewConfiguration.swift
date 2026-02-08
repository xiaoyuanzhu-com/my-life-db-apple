//
//  WebViewConfiguration.swift
//  MyLifeDB
//
//  Factory for WKWebViewConfiguration used by the hybrid WebView layer.
//  Creates a shared configuration with JavaScript bridge, platform injection,
//  and media playback settings.
//

import WebKit

enum WebViewConfiguration {

    /// Shared process pool — ensures cookies and sessions persist across any WKWebView instances.
    static let processPool = WKProcessPool()

    /// Create a configured WKWebViewConfiguration for the hybrid shell.
    ///
    /// - Parameter bridgeHandler: The native bridge message handler for Web-to-Native communication.
    /// - Returns: A fully configured `WKWebViewConfiguration`.
    static func create(bridgeHandler: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = processPool

        // --- User Content Controller ---
        let contentController = WKUserContentController()

        // Register the native bridge message handler (Web calls: window.webkit.messageHandlers.native.postMessage(...))
        contentController.add(bridgeHandler, name: "native")

        // Inject platform detection script at document start (before any page JS runs)
        let platform: String
        #if os(iOS)
        platform = "ios"
        #elseif os(macOS)
        platform = "macos"
        #elseif os(visionOS)
        platform = "visionos"
        #else
        platform = "unknown"
        #endif

        let injectionScript = WKUserScript(
            source: """
                window.isNativeApp = true;
                window.nativePlatform = '\(platform)';
                """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(injectionScript)

        config.userContentController = contentController

        // --- Media Playback ---
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // --- Data Store ---
        // Use default persistent data store (cookies, local storage, etc. survive app restarts)
        config.websiteDataStore = .default()

        return config
    }
}
