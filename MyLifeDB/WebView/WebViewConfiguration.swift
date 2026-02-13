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
    static func create(bridgeHandler: NativeBridgeHandler) -> WebPage.Configuration {
        var config = WebPage.Configuration()

        // Register the native bridge URL scheme handler
        if let scheme = URLScheme("nativebridge") {
            config.urlSchemeHandlers[scheme] = bridgeHandler
        }

        return config
    }
}
