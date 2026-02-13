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
}
