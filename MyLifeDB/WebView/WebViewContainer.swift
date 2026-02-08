//
//  WebViewContainer.swift
//  MyLifeDB
//
//  SwiftUI representable that embeds the shared WKWebView from WebViewManager.
//  Uses a wrapper UIView/NSView that adds/removes the WKWebView as a subview,
//  so the WebView can be swapped in after initial creation.
//
//  Platform:
//  - iOS/visionOS: UIViewRepresentable
//  - macOS: NSViewRepresentable
//

import SwiftUI
import WebKit

#if os(iOS) || os(visionOS)

struct WebViewContainer: UIViewRepresentable {

    func makeUIView(context: Context) -> WebViewWrapperView {
        let wrapper = WebViewWrapperView()
        wrapper.embedWebView(WebViewManager.shared.webView)
        return wrapper
    }

    func updateUIView(_ wrapper: WebViewWrapperView, context: Context) {
        // If the WebView was created after makeUIView (e.g., setup hadn't finished),
        // embed it now.
        wrapper.embedWebView(WebViewManager.shared.webView)
    }
}

/// A plain UIView that hosts the WKWebView as a subview.
/// This allows SwiftUI's updateUIView to swap in the real WebView
/// after setup completes.
class WebViewWrapperView: UIView {

    private weak var currentWebView: WKWebView?

    func embedWebView(_ webView: WKWebView?) {
        // Already embedded
        if let webView = webView, webView === currentWebView, webView.superview === self {
            return
        }

        // Remove old WebView if different
        currentWebView?.removeFromSuperview()
        currentWebView = nil

        guard let webView = webView else { return }

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        currentWebView = webView
    }
}

#elseif os(macOS)

struct WebViewContainer: NSViewRepresentable {

    func makeNSView(context: Context) -> WebViewWrapperNSView {
        let wrapper = WebViewWrapperNSView()
        wrapper.embedWebView(WebViewManager.shared.webView)
        return wrapper
    }

    func updateNSView(_ wrapper: WebViewWrapperNSView, context: Context) {
        wrapper.embedWebView(WebViewManager.shared.webView)
    }
}

/// A plain NSView that hosts the WKWebView as a subview.
class WebViewWrapperNSView: NSView {

    private weak var currentWebView: WKWebView?

    func embedWebView(_ webView: WKWebView?) {
        if let webView = webView, webView === currentWebView, webView.superview === self {
            return
        }

        currentWebView?.removeFromSuperview()
        currentWebView = nil

        guard let webView = webView else { return }

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        currentWebView = webView
    }
}

#endif
