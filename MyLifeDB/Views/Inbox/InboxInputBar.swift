//
//  InboxInputBar.swift
//  MyLifeDB
//
//  Input bar for creating new inbox items.
//  Supports text input, file attachments via photo picker
//  or file importer, and send action.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - File Attachment

struct InboxFileAttachment: Identifiable {
    let id: String
    let filename: String
    let data: Data
    let mimeType: String
    let pickerItemID: String?

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }
}

// MARK: - Input Bar

struct InboxInputBar: View {
    let onSend: (String, [InboxFileAttachment]) -> Void

    @State private var text = ""
    @State private var attachments: [InboxFileAttachment] = []
    @State private var isSending = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                attachmentsPreview
            }

            HStack(alignment: .bottom, spacing: 12) {
                attachButton

                TextField("What's up?", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.platformGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                sendButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.platformBackground)
        .onChange(of: photoPickerItems) { _, newItems in
            Task { await handlePhotoPickerSelection(newItems) }
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
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func attachmentChip(_ attachment: InboxFileAttachment) -> some View {
        HStack(spacing: 6) {
            if attachment.isImage {
                #if os(iOS)
                if let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    fileIcon(for: attachment.mimeType)
                }
                #elseif os(macOS)
                if let nsImage = NSImage(data: attachment.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    fileIcon(for: attachment.mimeType)
                }
                #endif
            } else {
                fileIcon(for: attachment.mimeType)
            }

            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 100)

            Button {
                attachments.removeAll { $0.id == attachment.id }
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

    private func fileIcon(for mimeType: String) -> some View {
        let iconName: String = {
            if mimeType.hasPrefix("image/") { return "photo" }
            if mimeType.hasPrefix("video/") { return "video" }
            if mimeType.hasPrefix("audio/") { return "waveform" }
            if mimeType == "application/pdf" { return "doc.richtext" }
            return "doc"
        }()

        return Image(systemName: iconName)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
    }

    // MARK: - Actions

    private func send() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }

        isSending = true
        onSend(trimmedText, attachments)

        text = ""
        attachments = []
        photoPickerItems = []
        isSending = false
    }

    // MARK: - File Handling

    private func handlePhotoPickerSelection(_ items: [PhotosPickerItem]) async {
        for item in items {
            if attachments.contains(where: { $0.pickerItemID == item.itemIdentifier }) {
                continue
            }
            if let data = try? await item.loadTransferable(type: Data.self) {
                let filename = "photo-\(UUID().uuidString.prefix(8)).jpg"
                let attachment = InboxFileAttachment(
                    id: UUID().uuidString,
                    filename: filename,
                    data: data,
                    mimeType: "image/jpeg",
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
                    let utType = UTType(filenameExtension: url.pathExtension)
                    let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"

                    let attachment = InboxFileAttachment(
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
            print("[InboxInputBar] File import failed: \(error)")
        }
    }
}
