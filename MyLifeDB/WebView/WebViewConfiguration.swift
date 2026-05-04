//
//  WebViewConfiguration.swift
//  MyLifeDB
//
//  Factory for WebPage.Configuration used by the hybrid WebView layer.
//

import WebKit

enum WebViewConfiguration {

    /// Create a configured WebPage.Configuration for the hybrid shell.
    ///
    /// The native bridge is registered as a WKScriptMessageHandlerWithReply on
    /// the user content controller (see TabWebViewModel.init), not here.
    ///
    /// - Parameter userContentController: The user content controller holding
    ///   the WKUserScript for the bridge polyfill and the script message
    ///   handler that backs window.webkit.messageHandlers.native.
    /// - Returns: A fully configured `WebPage.Configuration`.
    static func create(
        userContentController: WKUserContentController
    ) -> WebPage.Configuration {
        var config = WebPage.Configuration()

        // Explicitly use the default persistent data store so all WebPage
        // instances share the same cookie jar.
        config.websiteDataStore = .default()

        // Use the caller's user content controller (holds WKUserScript for
        // bridge polyfill and WKScriptMessageHandlerWithReply for native IPC).
        config.userContentController = userContentController

        return config
    }
}
