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

        // Provide the view model with a way to open URLs in the host app.
        //
        // We hand off via a Universal Link
        // (https://my.xiaoyuanzhu.com/ios-share/<uuid>) which the domain's
        // apple-app-site-association file declares for our App ID. iOS
        // recognizes the URL as belonging to MyLifeDB and routes it to
        // the app via NSUserActivity — this is the Apple-supported path
        // for share extensions to wake their containing app on iOS 18+.
        //
        // We previously fell back to a responder-chain UIApplication.open
        // hack for custom schemes. That path was killed by iOS 18 (the
        // deprecated `openURL:` selector force-returns NO, and the modern
        // 3-arg selector crashes on Swift's empty-dictionary singleton).
        // Universal Links make the fallback unnecessary.
        viewModel.openHostURL = { [weak self] url in
            await self?.openHostURL(url) ?? false
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
    private func openHostURL(_ url: URL) async -> Bool {
        guard let context = extensionContext else {
            print("[ShareExt] openHostURL: no extensionContext")
            return false
        }
        print("[ShareExt] extensionContext.open \(url)")
        return await withCheckedContinuation { continuation in
            context.open(url) { success in
                print("[ShareExt] extensionContext.open returned \(success)")
                continuation.resume(returning: success)
            }
        }
    }
}
