//
//  ClaudeWebView.swift
//  MyLifeDB
//
//  WebView-backed Claude tab. Navigates the shared WKWebView to the
//  web frontend's "/claude" route which displays the Claude Code
//  session list, chat interface, and terminal UI.
//

import SwiftUI

struct ClaudeWebView: View {
    var body: some View {
        WebViewContainer()
            .onAppear {
                WebViewManager.shared.navigateTo(path: "/claude")
            }
    }
}

#Preview {
    ClaudeWebView()
}
