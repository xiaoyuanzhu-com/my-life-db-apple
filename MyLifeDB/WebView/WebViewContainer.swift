//
//  WebViewContainer.swift
//  MyLifeDB
//
//  SwiftUI view that embeds a WebPage via the native WebView component (iOS 26+).
//  Replaces the previous UIViewRepresentable/NSViewRepresentable wrapper.
//

import SwiftUI
import WebKit

struct WebViewContainer: View {

    let viewModel: TabWebViewModel

    var body: some View {
        WebView(viewModel.webPage)
            .ignoresSafeArea()
            // Paint `webBackground` behind the WebView so the brief moment
            // before page content renders matches the page's `--background`
            // token in both light and dark mode (the WKWebView's backing
            // layer is otherwise dark on first appearance).
            .background(Color.webBackground.ignoresSafeArea())
            #if os(iOS)
            // Re-inject safe area insets when the device rotates.
            // `.ignoresSafeArea()` zeroes out the CSS env() variables,
            // so we pass the real insets via JS as CSS custom properties.
            // Using the view width as a proxy — it changes on rotation,
            // triggering the re-injection with updated inset values.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { _ in
                Task { await viewModel.injectSafeAreaInsets() }
            }
            #endif
    }
}
