//
//  ShareView.swift
//  MyLifeDBShareExtension
//
//  SwiftUI compose view for the Share Extension.
//  Displays a compose sheet where users can add a note
//  and preview what they're sharing before sending to Inbox.
//

import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    @Bindable var viewModel: ShareViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    loadingView

                case .notAuthenticated:
                    notAuthenticatedView

                case .ready:
                    composeView

                case .uploading:
                    uploadingView

                case .success:
                    successView

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Send to Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.state != .uploading {
                        Button("Cancel") { onDismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compose

    private var composeView: some View {
        Form {
            Section {
                ForEach(viewModel.items) { item in
                    contentPreviewRow(for: item)
                }
            }

            Section {
                TextField("Add a note...", text: $viewModel.userNote, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Button {
                    Task { await viewModel.upload() }
                } label: {
                    Text("Send")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Content Preview Row

    @ViewBuilder
    private func contentPreviewRow(for item: SharedContent) -> some View {
        switch item.kind {
        case .url(let url):
            urlPreview(url: url)

        case .text(let text):
            textPreview(text: text)

        case .imageFile(_, let data, _, let thumbnail):
            imagePreview(thumbnail: thumbnail, fileSize: data.count)

        case .videoFile(let filename, let data, _, let thumbnail):
            videoPreview(thumbnail: thumbnail, filename: filename, fileSize: data.count)

        case .audioFile(let filename, let data, _):
            fileRow(icon: "waveform", filename: filename, fileSize: data.count)

        case .genericFile(let filename, let data, _, let utType):
            fileRow(icon: iconName(for: utType), filename: filename, fileSize: data.count)
        }
    }

    // MARK: - URL Preview

    private func urlPreview(url: URL) -> some View {
        LinkPreviewView(url: url)
            .frame(minHeight: 60, maxHeight: 200)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    // MARK: - Text Preview

    private func textPreview(text: String) -> some View {
        Text(text.prefix(500))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Image Preview

    private func imagePreview(thumbnail: UIImage, fileSize: Int) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - Video Preview

    private func videoPreview(thumbnail: UIImage?, filename: String, fileSize: Int) -> some View {
        VStack(spacing: 6) {
            if let thumbnail {
                ZStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 4)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                    Text(filename)
                        .font(.callout)
                        .lineLimit(1)
                }
            }

            Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: - File Row

    private func fileRow(icon: String, filename: String, fileSize: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.callout)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    // MARK: - File Icon Mapping

    private func iconName(for utType: UTType?) -> String {
        guard let utType else { return "doc" }

        if utType.conforms(to: .pdf) { return "doc.richtext" }
        if utType.conforms(to: .archive) { return "doc.zipper" }
        if utType.conforms(to: .vCard) { return "person.crop.rectangle" }
        if utType.conforms(to: .spreadsheet) { return "tablecells" }
        if utType.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if utType.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if utType.conforms(to: .text) { return "doc.text" }

        return "doc"
    }

    // MARK: - Uploading

    private var uploadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Sending to Inbox...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Sent to Inbox")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Auto-dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        }
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Not Signed In")
                .font(.headline)
            Text("Please open MyLifeDB and sign in first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Send")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.bordered)
                Button("Retry") {
                    Task { await viewModel.upload() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Link Preview (UIViewRepresentable)

struct LinkPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LPLinkView {
        let linkView = LPLinkView(url: url)

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, _ in
            if let metadata {
                DispatchQueue.main.async {
                    linkView.metadata = metadata
                }
            }
        }

        return linkView
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {}
}
