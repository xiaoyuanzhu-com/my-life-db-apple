//
//  PickAndUploadFiles.swift
//  MyLifeDB
//
//  Implements the `pickAndUploadFiles` native bridge action.
//
//  iOS WKWebView's <input type="file"> click is gated by an in-gesture user
//  activation token, which Radix UI's deferred DropdownMenu callback consumes
//  before it ever reaches WebKit's file input. The web composer's "Upload
//  files" item is wired through that deferred path, so the picker silently
//  never opens.
//
//  This action sidesteps the issue end-to-end: JS calls the bridge, Swift
//  presents UIDocumentPickerViewController, then uploads each picked file
//  via APIClient and returns the resulting Attachment records as JSON. JS
//  inserts them into the composer's attachments hook as already-ready —
//  no File reconstruction, no base64 across the bridge.
//

#if os(iOS)

import Foundation
import UIKit
import UniformTypeIdentifiers

// MARK: - Wire model

/// Mirrors backend POST /api/agent/attachments response.
/// Field names match the JS `Attachment` interface (camelCase, no transform).
struct AgentAttachment: Decodable {
    let storageId: String
    let filename: String
    let absolutePath: String
    let size: Int64
    let contentType: String?

    func toJSONDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "storageId": storageId,
            "filename": filename,
            "absolutePath": absolutePath,
            "size": size,
        ]
        if let contentType { dict["contentType"] = contentType }
        return dict
    }
}

// MARK: - URL → MIME

private extension URL {
    var inferredMimeType: String {
        guard let utType = UTType(filenameExtension: pathExtension.lowercased()),
              let mime = utType.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mime
    }
}

// MARK: - Picker delegate coordinator

/// Bridges UIDocumentPickerDelegate callbacks back to the awaiting Task.
/// Held strongly by NativeBridgeHandler for the duration of one picker
/// session (UIDocumentPickerViewController.delegate is `weak`).
@MainActor
final class FilePickerCoordinator: NSObject, UIDocumentPickerDelegate {

    private var didComplete = false
    private let onResult: ([URL]) -> Void

    init(onResult: @escaping ([URL]) -> Void) {
        self.onResult = onResult
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        complete(with: urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        complete(with: [])
    }

    private func complete(with urls: [URL]) {
        guard !didComplete else { return }
        didComplete = true
        onResult(urls)
    }
}

// MARK: - NativeBridgeHandler extension

extension NativeBridgeHandler {

    /// Presents the document picker, uploads each picked file to the backend,
    /// and returns a JSON-ready dictionary `{ "attachments": [...] }`. Always
    /// returns a 200-shaped payload — failures show up as a missing entry in
    /// the array (caller decides whether to surface). Cancel returns an
    /// empty array.
    @MainActor
    func handlePickAndUploadFiles(storageId: String?) async -> [String: Any] {
        let urls = await presentDocumentPicker()
        guard !urls.isEmpty else {
            return ["attachments": []]
        }

        var current = storageId
        var attachments: [[String: Any]] = []
        for url in urls {
            // asCopy: true gives us a sandbox-local copy; no
            // startAccessingSecurityScopedResource dance required.
            guard let data = try? Data(contentsOf: url) else {
                print("[NativeBridge] pickAndUploadFiles: failed to read \(url.lastPathComponent)")
                continue
            }
            do {
                var fields: [String: String] = [:]
                if let cur = current { fields["storageId"] = cur }
                let attachment: AgentAttachment = try await APIClient.shared.uploadMultipart(
                    path: "/api/agent/attachments",
                    formFields: fields,
                    files: [(
                        name: "file",
                        filename: url.lastPathComponent,
                        data: data,
                        mimeType: url.inferredMimeType
                    )]
                )
                // First upload mints the storageId; subsequent uploads in the
                // same picker session reuse it so all files land in the same
                // session folder.
                current = attachment.storageId
                attachments.append(attachment.toJSONDictionary())
            } catch {
                print("[NativeBridge] pickAndUploadFiles: upload failed for \(url.lastPathComponent): \(error)")
            }
        }
        return ["attachments": attachments]
    }

    /// Shows UIDocumentPickerViewController and resolves with the picked URLs
    /// (empty on cancel). The Coordinator is retained on `self` for the
    /// lifetime of the picker.
    @MainActor
    private func presentDocumentPicker() async -> [URL] {
        await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
            let coordinator = FilePickerCoordinator { [weak self] urls in
                self?.activeFilePickerCoordinator = nil
                cont.resume(returning: urls)
            }
            activeFilePickerCoordinator = coordinator

            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.allowsMultipleSelection = true
            picker.shouldShowFileExtensions = true
            picker.delegate = coordinator

            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                    ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  var topVC = scene.keyWindow?.rootViewController else {
                activeFilePickerCoordinator = nil
                cont.resume(returning: [])
                return
            }
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(picker, animated: true)
        }
    }
}

#endif
