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

struct FileViewerView: View {

    // MARK: - Initializers

    /// Create a viewer when you already have file metadata.
    init(file: FileRecord) {
        self._resolvedFile = State(initialValue: file)
        self.filePath = file.path
        self.fileName = file.name
        self._needsFetch = State(initialValue: false)
    }

    /// Create a viewer that fetches metadata on appear.
    init(filePath: String, fileName: String) {
        self._resolvedFile = State(initialValue: nil)
        self.filePath = filePath
        self.fileName = fileName
        self._needsFetch = State(initialValue: true)
    }

    // MARK: - Properties

    private let filePath: String
    private let fileName: String

    @State private var resolvedFile: FileRecord?
    @State private var needsFetch: Bool
    @State private var isLoading = false
    @State private var error: Error?

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
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        #if !os(macOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .task {
            if needsFetch {
                await loadFileInfo()
            }
        }
    }

    // MARK: - Content Dispatch

    @ViewBuilder
    private func fileContentView(_ file: FileRecord) -> some View {
        if file.isImage {
            ImageFileView(path: filePath)
        } else if file.isText {
            TextFileView(path: filePath)
        } else if file.isPDF {
            PDFFileView(path: filePath)
        } else if file.isVideo {
            VideoFileView(path: filePath)
        } else if file.isAudio {
            AudioFileView(path: filePath, fileName: fileName)
        } else {
            GenericFileInfoView(file: file, filePath: filePath)
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
