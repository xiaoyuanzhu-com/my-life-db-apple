//
//  InboxWebView.swift
//  MyLifeDB
//
//  WebView-backed inbox tab. Navigates the shared WKWebView to the
//  web frontend's home route ("/") which displays the full inbox feed
//  with omni-input, pinned tags, file cards, and search.
//

import SwiftUI

struct InboxWebView: View {
    var body: some View {
        WebViewContainer()
            .onAppear {
                WebViewManager.shared.navigateTo(path: "/")
            }
    }
}

#Preview {
    InboxWebView()
}
