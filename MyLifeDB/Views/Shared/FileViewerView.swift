//
//  FileViewerView.swift
//  MyLifeDB
//
//  Reusable native file viewer that can be presented from anywhere
//  (Library, Inbox, etc.). Dispatches to the appropriate type-specific
//  viewer based on the file's MIME type, with a fallback for
//  unsupported formats.
//
//  Usage:
//    // When you already have a FileRecord:
//    FileViewerView(file: someFileRecord)
//
//    // When you only have a path (metadata will be fetched):
//    FileViewerView(filePath: "inbox/photo.jpg", fileName: "photo.jpg")
//

import SwiftUI

// MARK: - File Preview Environment

/// Identifiable wrapper for preview presentation.
struct FilePreviewDestination: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let file: FileRecord?

    init(path: String, name: String, file: FileRecord? = nil) {
        self.path = path
        self.name = name
        self.file = file
    }
}

private struct FilePreviewActionKey: EnvironmentKey {
    static var defaultValue: ((String, String, FileRecord?) -> Void)? = nil
}

private struct PreviewNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var openFilePreview: ((String, String, FileRecord?) -> Void)? {
        get { self[FilePreviewActionKey.self] }
        set { self[FilePreviewActionKey.self] = newValue }
    }

    var previewNamespace: Namespace.ID? {
        get { self[PreviewNamespaceKey.self] }
        set { self[PreviewNamespaceKey.self] = newValue }
    }
}

// MARK: - Preview Source Modifier

extension View {
    /// Apply to thumbnail/card views that serve as the zoom-animation source.
    @ViewBuilder
    func previewSource(path: String, namespace: Namespace.ID?) -> some View {
        #if os(macOS)
        self
        #else
        if let ns = namespace {
            self.matchedTransitionSource(id: path, in: ns)
        } else {
            self
        }
        #endif
    }
}

// MARK: - FileViewerView

struct FileViewerView: View {

    // MARK: - Initializers

    /// Create a viewer when you already have file metadata.
    init(file: FileRecord, onDismiss: (() -> Void)? = nil) {
        self._resolvedFile = State(initialValue: file)
        self.filePath = file.path
        self.fileName = file.name
        self._needsFetch = State(initialValue: false)
        self.onDismiss = onDismiss
    }

    /// Create a viewer that fetches metadata on appear.
    init(filePath: String, fileName: String, onDismiss: (() -> Void)? = nil) {
        self._resolvedFile = State(initialValue: nil)
        self.filePath = filePath
        self.fileName = fileName
        self._needsFetch = State(initialValue: true)
        self.onDismiss = onDismiss
    }

    // MARK: - Properties

    private let filePath: String
    private let fileName: String
    private let onDismiss: (() -> Void)?

    @State private var resolvedFile: FileRecord?
    @State private var needsFetch: Bool
    @State private var isLoading = false
    @State private var error: Error?
    @State private var isDownloadingForShare = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        Group {
            if let file = resolvedFile {
                fileContentView(file)
            } else if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else {
                loadingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: onDismiss != nil ? "xmark" : "chevron.left")
                    .glassEffect(.regular.interactive, in: .circle)
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                guard !isDownloadingForShare else { return }
                isDownloadingForShare = true
                Task {
                    defer { isDownloadingForShare = false }
                    do {
                        let data = try await APIClient.shared.getRawFile(path: filePath)
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                        try data.write(to: tempURL)
                        presentShareSheet(items: [tempURL])
                    } catch {
                        print("[FileViewer] Failed to download file for sharing: \(error)")
                    }
                }
            } label: {
                Group {
                    if isDownloadingForShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .glassEffect(.regular.interactive, in: .circle)
            }
            .disabled(isDownloadingForShare)
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .task {
            if needsFetch {
                await loadFileInfo()
            }
        }
    }

    // MARK: - Content Dispatch

    private var dismissAction: () -> Void {
        if let onDismiss { onDismiss } else { { dismiss() } }
    }

    @ViewBuilder
    private func fileContentView(_ file: FileRecord) -> some View {
        if file.isImage {
            ImageFileView(path: filePath, onDismiss: dismissAction)
        } else if file.isText {
            TextFileView(path: filePath)
                .contentShape(Rectangle())
                .onTapGesture { dismissAction() }
        } else if file.isPDF {
            PDFFileView(path: filePath)
                .contentShape(Rectangle())
                .onTapGesture { dismissAction() }
        } else if file.isVideo {
            VideoFileView(path: filePath)
                .contentShape(Rectangle())
                .onTapGesture { dismissAction() }
        } else if file.isAudio {
            AudioFileView(path: filePath, fileName: fileName)
                .contentShape(Rectangle())
                .onTapGesture { dismissAction() }
        } else {
            GenericFileInfoView(file: file, filePath: filePath)
                .contentShape(Rectangle())
                .onTapGesture { dismissAction() }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading file...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Failed to Load File")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task { await loadFileInfo() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Fetching

    private func loadFileInfo() async {
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.library.getFileInfo(path: filePath)
            resolvedFile = response.file
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
