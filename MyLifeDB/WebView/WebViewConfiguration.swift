//
//  WebViewConfiguration.swift
//  MyLifeDB
//
//  Factory for WebPage.Configuration used by the hybrid WebView layer.
//  Registers the native bridge URL scheme handler.
//

import WebKit

enum WebViewConfiguration {

    /// Create a configured WebPage.Configuration for the hybrid shell.
    ///
    /// - Parameter bridgeHandler: The native bridge URL scheme handler for Web-to-Native communication.
    /// - Returns: A fully configured `WebPage.Configuration`.
    static func create(
        bridgeHandler: NativeBridgeHandler,
        userContentController: WKUserContentController
    ) -> WebPage.Configuration {
        var config = WebPage.Configuration()

        // Explicitly use the default persistent data store so all WebPage
        // instances share the same cookie jar.
        config.websiteDataStore = .default()

        // Use the caller's user content controller (holds WKUserScript for bridge polyfill).
        config.userContentController = userContentController

        // Register the native bridge URL scheme handler
        if let scheme = URLScheme("nativebridge") {
            config.urlSchemeHandlers[scheme] = bridgeHandler
        }

        return config
    }
}
