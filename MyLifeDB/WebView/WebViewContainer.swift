//
//  WebViewContainer.swift
//  MyLifeDB
//
//  SwiftUI representable that embeds the WKWebView from a TabWebViewModel.
//  Each tab creates its own container with its own view model.
//
//  Platform:
//  - iOS/visionOS: UIViewRepresentable
//  - macOS: NSViewRepresentable
//

import SwiftUI
import WebKit

#if os(iOS) || os(visionOS)

struct WebViewContainer: UIViewRepresentable {

    let viewModel: TabWebViewModel

    func makeUIView(context: Context) -> WebViewWrapperView {
        let wrapper = WebViewWrapperView()
        wrapper.embedWebView(viewModel.webView)
        return wrapper
    }

    func updateUIView(_ wrapper: WebViewWrapperView, context: Context) {
        // If the WebView was created after makeUIView (e.g., setup hadn't finished),
        // embed it now.
        wrapper.embedWebView(viewModel.webView)
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
            // Pin to safe area on top and bottom so content doesn't overlap
            // the status bar / Dynamic Island at the top or the tab bar at the bottom.
            webView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        currentWebView = webView
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let webView = currentWebView else { return }

        // Find the UINavigationController's interactive pop gesture recognizer
        // and make the WebView's scroll pan gesture defer to it, so the
        // standard iOS swipe-back-from-edge works even over a WKWebView.
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let nav = next as? UINavigationController,
               let popGesture = nav.interactivePopGestureRecognizer {
                webView.scrollView.panGestureRecognizer.require(toFail: popGesture)
                break
            }
            responder = next
        }
    }
}

#elseif os(macOS)

struct WebViewContainer: NSViewRepresentable {

    let viewModel: TabWebViewModel

    func makeNSView(context: Context) -> WebViewWrapperNSView {
        let wrapper = WebViewWrapperNSView()
        wrapper.embedWebView(viewModel.webView)
        return wrapper
    }

    func updateNSView(_ wrapper: WebViewWrapperNSView, context: Context) {
        wrapper.embedWebView(viewModel.webView)
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
