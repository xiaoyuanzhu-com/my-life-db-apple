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

    /// Create a configured WKWebViewConfiguration for the hybrid shell.
    ///
    /// - Parameter bridgeHandler: The native bridge message handler for Web-to-Native communication.
    /// - Returns: A fully configured `WKWebViewConfiguration`.
    static func create(bridgeHandler: WKScriptMessageHandler, isDarkMode: Bool = false) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

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

        let theme = isDarkMode ? "dark" : "light"

        let injectionScript = WKUserScript(
            source: """
                window.isNativeApp = true;
                window.nativePlatform = '\(platform)';

                // Apply theme immediately at document start to prevent light-mode flash.
                // The native bridge (syncTheme) will handle runtime appearance changes later.
                document.addEventListener('DOMContentLoaded', function() {
                    document.documentElement.classList.toggle('dark', \(isDarkMode));
                    document.documentElement.style.colorScheme = '\(theme)';
                });
                """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(injectionScript)

        config.userContentController = contentController

        // --- Media Playback ---
        #if os(iOS) || os(visionOS)
        config.allowsInlineMediaPlayback = true
        #endif
        config.mediaTypesRequiringUserActionForPlayback = []

        // --- Data Store ---
        // Use default persistent data store (cookies, local storage, etc. survive app restarts)
        config.websiteDataStore = .default()

        return config
    }
}
