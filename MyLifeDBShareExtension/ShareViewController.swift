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
        // NSExtensionContext.open(_:completionHandler:) wakes the main app
        // via its registered URL scheme; we use it to hand the staged
        // share folder over to MyLifeDB for the actual upload.
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

    /// Best-effort wake the host app via its URL scheme. Tries the
    /// official extension-context API first; falls back to walking up
    /// the responder chain to invoke `UIApplication.open(_:options:completionHandler:)`,
    /// since `NSExtensionContext.open(_:)` is documented as supported
    /// for Today/Action extensions but not Share extensions and tends
    /// to return `false` here.
    ///
    /// Returns whether *some* path believed it triggered the open.
    /// Either way, the share is already staged on disk, so the main
    /// app's `drainAll()` on next launch/foreground will finish the
    /// upload regardless of this result.
    @MainActor
    private func openHostURL(_ url: URL) async -> Bool {
        if let context = extensionContext {
            print("[ShareExt] trying extensionContext.open for \(url)")
            let success = await withCheckedContinuation { continuation in
                context.open(url) { success in
                    continuation.resume(returning: success)
                }
            }
            print("[ShareExt] extensionContext.open returned \(success)")
            if success { return true }
        }
        let chained = openURLViaResponderChain(url)
        print("[ShareExt] responder-chain openURL returned \(chained)")
        return chained
    }

    /// Fallback: walk the responder chain looking for an object that
    /// responds to `openURL:`. On iOS the running `UIApplication`
    /// instance does — extensions can't import the symbol, but the
    /// selector dispatch still works.
    @MainActor
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector) {
                print("[ShareExt] responder-chain openURL: dispatching to \(type(of: r))")
                _ = r.perform(selector, with: url)
                return true
            }
            responder = r.next
        }
        print("[ShareExt] responder-chain openURL: no responder found")
        return false
    }
}
