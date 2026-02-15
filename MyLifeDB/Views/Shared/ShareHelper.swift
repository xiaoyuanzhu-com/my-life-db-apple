//
//  ShareHelper.swift
//  MyLifeDB
//
//  Presents the platform-native share sheet with the given items.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
func presentShareSheet(items: [Any]) {
    guard !items.isEmpty else { return }

    #if os(iOS)
    let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          var topVC = scene.keyWindow?.rootViewController else { return }

    // Walk up the presented view controller chain to find the topmost one
    while let presented = topVC.presentedViewController {
        topVC = presented
    }

    if let popover = activityVC.popoverPresentationController {
        popover.sourceView = topVC.view
        let bounds = topVC.view.bounds
        popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }

    topVC.present(activityVC, animated: true)
    #elseif os(macOS)
    guard let window = NSApp?.mainWindow else { return }
    let picker = NSSharingServicePicker(items: items)
    picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    #endif
}
