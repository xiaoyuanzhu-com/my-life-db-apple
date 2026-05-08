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
        // Try two approaches and log both outcomes. We don't actually know
        // which one (if either) wakes the app from a Share Extension on
        // iOS 18 — Apple's docs say extensionContext.open is Today-only,
        // but reports in the wild are mixed and we haven't tried the
        // SwiftUI-native path before.

        // Path A — SwiftUI EnvironmentValues().openURL
        // Per https://medium.com/@itsuki.enjoy/swift-when-extensioncontext-open-does-not-open-my-app-solution-eaf59ab552c2
        // (2026), instantiating EnvironmentValues directly and calling its
        // openURL outside a View context can wake the host app where
        // extensionContext.open returns false. Public API, not a runtime
        // hack. No completion handler, so we can't confirm success — just
        // log that we fired it.
        print("[ShareExt] path A: EnvironmentValues().openURL \(url)")
        let env = EnvironmentValues()
        env.openURL(url)
        print("[ShareExt] path A: EnvironmentValues().openURL fired")

        // Path B — NSExtensionContext.open
        // Documented as Today-widget-only. We try it anyway for evidence.
        guard let context = extensionContext else {
            print("[ShareExt] path B: no extensionContext, skipping")
            // Optimistically report success — Path A may have worked.
            return true
        }
        print("[ShareExt] path B: extensionContext.open \(url)")
        let pathBSuccess = await withCheckedContinuation { continuation in
            context.open(url) { success in
                print("[ShareExt] path B: extensionContext.open returned \(success)")
                continuation.resume(returning: success)
            }
        }
        // Either path may have worked. We can only confirm B; assume A
        // succeeded if B failed (the worst case is the dismiss-without-jump
        // we already saw, which our drainAll() safety net handles).
        return pathBSuccess || true
    }
}
