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

    /// Bridge `NSExtensionContext.open(_:completionHandler:)` into an
    /// `async` boolean for the view model.
    @MainActor
    private func openHostURL(_ url: URL) async -> Bool {
        guard let context = extensionContext else { return false }
        return await withCheckedContinuation { continuation in
            context.open(url) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
