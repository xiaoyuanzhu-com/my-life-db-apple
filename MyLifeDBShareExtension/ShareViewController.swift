//
//  ShareViewController.swift
//  MyLifeDBShareExtension
//
//  Entry point for the Share Extension.
//  Hosts the SwiftUI ShareView and bridges the extension context.
//

import UIKit
import SwiftUI

class ShareViewController: UIViewController {

    private let viewModel = ShareViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Provide the view model with a way to wake the host app.
        //
        // We hand off via a Universal Link
        // (https://my.xiaoyuanzhu.com/ios-share/<uuid>) which the domain's
        // apple-app-site-association file declares for our App ID.
        //
        // The actual call uses SwiftUI's `EnvironmentValues().openURL(_:)`.
        // We tried the obvious alternatives first; only this one works:
        //
        //   - `NSExtensionContext.open` — Apple documents this as Today-
        //     widget-only. From a Share Extension, the completion handler
        //     fires with `success = false` and the host app is not woken.
        //   - Responder-chain `UIApplication.openURL:` — the deprecated
        //     single-arg selector force-returns NO on iOS 18 and logs
        //     "BUG IN CLIENT OF UIKIT". The modern 3-arg selector
        //     (`openURL:options:completionHandler:`) crashes inside UIKit's
        //     KVC probe of the options dictionary.
        //
        // Instantiating `EnvironmentValues()` directly and calling its
        // `openURL` is public API (no runtime hack, no deprecated
        // selector) and works from a Share Extension to wake the
        // containing app via a Universal Link. Reference:
        // https://medium.com/@itsuki.enjoy/swift-when-extensioncontext-open-does-not-open-my-app-solution-eaf59ab552c2
        viewModel.openHostURL = { url in
            await Self.openHostURL(url)
        }

        let shareView = ShareView(viewModel: viewModel) { [weak self] in
            self?.dismissExtension()
        }

        let hostingController = UIHostingController(rootView: shareView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.didMove(toParent: self)

        // Begin extracting content from the share sheet
        Task {
            await viewModel.extractContent(from: extensionContext?.inputItems ?? [])
        }
    }

    private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    @MainActor
    private static func openHostURL(_ url: URL) async -> Bool {
        EnvironmentValues().openURL(url)
        // openURL has no completion handler, so we can't observe whether
        // the open actually succeeded. Report success optimistically; the
        // main app's drainAll() on next launch covers any case where it
        // didn't.
        return true
    }
}
