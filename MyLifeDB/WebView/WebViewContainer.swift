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
    }
}
