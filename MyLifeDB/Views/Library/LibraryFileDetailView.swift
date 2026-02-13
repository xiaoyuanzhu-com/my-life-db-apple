//
//  LibraryFileDetailView.swift
//  MyLifeDB
//
//  File detail screen that loads FileInfoResponse from the API,
//  then dispatches to the appropriate native content viewer
//  based on file type.
//

import SwiftUI

struct LibraryFileDetailView: View {

    let filePath: String
    let fileName: String

    @State private var fileInfo: FileInfoResponse?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else if let fileInfo = fileInfo {
                fileContentView(fileInfo.file)
            }
        }
        .navigationTitle(fileName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadFileInfo()
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
            fileInfo = try await APIClient.shared.library.getFileInfo(path: filePath)
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
