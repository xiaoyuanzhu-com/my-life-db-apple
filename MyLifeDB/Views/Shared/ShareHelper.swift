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
          let rootVC = scene.keyWindow?.rootViewController else { return }

    if let popover = activityVC.popoverPresentationController {
        popover.sourceView = rootVC.view
        let bounds = rootVC.view.bounds
        popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }

    rootVC.present(activityVC, animated: true)
    #elseif os(macOS)
    guard let window = NSApp?.mainWindow else { return }
    let picker = NSSharingServicePicker(items: items)
    picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    #endif
}
