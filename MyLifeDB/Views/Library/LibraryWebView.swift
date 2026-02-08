//
//  LibraryWebView.swift
//  MyLifeDB
//
//  WebView-backed library tab. Navigates the shared WKWebView to the
//  web frontend's "/library" route which displays the file tree,
//  folder navigation, file viewer, and breadcrumbs.
//

import SwiftUI

struct LibraryWebView: View {
    var body: some View {
        WebViewContainer()
            .onAppear {
                WebViewManager.shared.navigateTo(path: "/library")
            }
    }
}

#Preview {
    LibraryWebView()
}
