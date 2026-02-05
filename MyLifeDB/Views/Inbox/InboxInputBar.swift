//
//  InboxInputBar.swift
//  MyLifeDB
//
//  Input bar for creating new inbox items.
//  Supports text input, file attachments, and send action.
//

import SwiftUI
import PhotosUI

struct InboxInputBar: View {
    /// Current text input
    @Binding var text: String

    /// Callback when user sends content
    let onSend: (String, [FileAttachment]) -> Void

    /// File attachments
    @State private var attachments: [FileAttachment] = []

    /// Whether sending is in progress
    @State private var isSending = false

    /// Photo picker selection
    @State private var photoPickerItems: [PhotosPickerItem] = []

    /// Show file importer
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            // Attachments preview
            if !attachments.isEmpty {
                attachmentsPreview
            }

            // Input row
            HStack(alignment: .bottom, spacing: 12) {
                // Attach button
                attachButton

                // Text field
                TextField("What's up?", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.platformGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Send button
                sendButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.platformBackground)
        .onChange(of: photoPickerItems) { _, newItems in
            Task {
                await handlePhotoPickerSelection(newItems)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImporterResult(result)
        }
    }

    // MARK: - Attach Button

    private var attachButton: some View {
        Menu {
            PhotosPicker(
                selection: $photoPickerItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Files", systemImage: "folder")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title)
                .foregroundStyle(canSend ? .blue : .secondary)
        }
        .disabled(!canSend || isSending)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    // MARK: - Attachments Preview

    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        removeAttachment(attachment)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func send() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }

        isSending = true

        // Call the callback
        onSend(trimmedText, attachments)

        // Clear state
        text = ""
        attachments = []
        photoPickerItems = []
        isSending = false
    }

    private func removeAttachment(_ attachment: FileAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - File Handling

    private func handlePhotoPickerSelection(_ items: [PhotosPickerItem]) async {
        for item in items {
            // Skip if already added
            if attachments.contains(where: { $0.pickerItemID == item.itemIdentifier }) {
                continue
            }

            // Load image data
            if let data = try? await item.loadTransferable(type: Data.self) {
                let filename = "photo-\(UUID().uuidString.prefix(8)).jpg"
                let mimeType = "image/jpeg"

                let attachment = FileAttachment(
                    id: UUID().uuidString,
                    filename: filename,
                    data: data,
                    mimeType: mimeType,
                    pickerItemID: item.itemIdentifier
                )
                attachments.append(attachment)
            }
        }
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                if let data = try? Data(contentsOf: url) {
                    let filename = url.lastPathComponent
                    let mimeType = mimeTypeForExtension(url.pathExtension)

                    let attachment = FileAttachment(
                        id: UUID().uuidString,
                        filename: filename,
                        data: data,
                        mimeType: mimeType,
                        pickerItemID: nil
                    )
                    attachments.append(attachment)
                }
            }

        case .failure(let error):
            print("File import failed: \(error)")
        }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - File Attachment

struct FileAttachment: Identifiable {
    let id: String
    let filename: String
    let data: Data
    let mimeType: String
    let pickerItemID: String?

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }
}

// MARK: - Attachment Chip

struct AttachmentChip: View {
    let attachment: FileAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Thumbnail or icon
            if attachment.isImage {
                #if os(iOS)
                if let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: iconForMimeType(attachment.mimeType))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                #elseif os(macOS)
                if let nsImage = NSImage(data: attachment.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: iconForMimeType(attachment.mimeType))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                #endif
            } else {
                Image(systemName: iconForMimeType(attachment.mimeType))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            // Filename
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 100)

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.platformGray5)
        .clipShape(Capsule())
    }

    private func iconForMimeType(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        InboxInputBar(text: .constant("")) { text, files in
            print("Send: \(text), files: \(files.count)")
        }
    }
    .background(Color.platformGroupedBackground)
}
