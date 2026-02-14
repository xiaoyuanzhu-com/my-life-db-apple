//
//  LibraryFolderView.swift
//  MyLifeDB
//
//  Displays the contents of a single library directory.
//  Handles loading, error, empty, and content states.
//  Supports grid and list view modes.
//  Supports file upload and new folder creation.
//

import SwiftUI
import UniformTypeIdentifiers

struct LibraryFolderView: View {

    let folderPath: String
    let folderName: String
    @Binding var viewMode: LibraryViewMode

    @State private var children: [FileTreeNode] = []
    @State private var isLoading = false
    @State private var error: Error?

    // Upload state
    @State private var showFilePicker = false
    @State private var isUploading = false
    @State private var uploadProgress: (current: Int, total: Int)?
    @State private var uploadError: String?
    @State private var showUploadError = false

    // New folder state
    @State private var showNewFolderDialog = false
    @State private var newFolderName = ""

    var body: some View {
        Group {
            if isLoading && children.isEmpty {
                loadingView
            } else if let error = error, children.isEmpty {
                errorView(error)
            } else if children.isEmpty && !isLoading {
                emptyView
            } else {
                contentView
            }
        }
        .overlay {
            if isUploading {
                uploadOverlay
            }
        }
        .navigationTitle(folderName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 4) {
                    // Upload button
                    Button {
                        showFilePicker = true
                    } label: {
                        Image(systemName: "arrow.up.doc")
                    }
                    .accessibilityLabel("Upload files")
                    .disabled(isUploading)

                    // New folder button
                    Button {
                        newFolderName = ""
                        showNewFolderDialog = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("New folder")

                    // View mode toggle
                    Button {
                        withAnimation {
                            viewMode = viewMode == .grid ? .list : .grid
                        }
                    } label: {
                        Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    }
                    .accessibilityLabel(viewMode == .grid ? "Switch to list view" : "Switch to grid view")
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("New Folder", isPresented: $showNewFolderDialog) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                Task { await createFolder() }
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for the new folder.")
        }
        .alert("Upload Failed", isPresented: $showUploadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uploadError ?? "An unknown error occurred.")
        }
        .task {
            if children.isEmpty {
                await loadChildren()
            }
        }
        .refreshable {
            await loadChildren()
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            LibraryGridView(children: children, folderPath: folderPath)
        case .list:
            LibraryListView(children: children, folderPath: folderPath)
        }
    }

    // MARK: - Upload Overlay

    private var uploadOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            if let progress = uploadProgress {
                Text("Uploading \(progress.current)/\(progress.total)...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Uploading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading...")
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

            Text("Failed to Load")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task { await loadChildren() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Empty Folder", systemImage: "folder")
        } description: {
            Text("This folder has no files or subfolders.")
        }
    }

    // MARK: - Data Fetching

    private func loadChildren() async {
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.library.getTree(path: folderPath, depth: 1)
            children = response.children
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - File Upload

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task { await uploadFiles(urls) }
        case .failure(let error):
            uploadError = error.localizedDescription
            showUploadError = true
        }
    }

    private func uploadFiles(_ urls: [URL]) async {
        isUploading = true
        uploadProgress = (current: 0, total: urls.count)

        var errors: [String] = []

        for (index, url) in urls.enumerated() {
            uploadProgress = (current: index + 1, total: urls.count)

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent

                // Determine MIME type from file extension
                let utType = UTType(filenameExtension: url.pathExtension)
                let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"

                let _ : SimpleUploadResponse = try await APIClient.shared.library.simpleUpload(
                    data: data,
                    filename: filename,
                    destination: folderPath,
                    mimeType: mimeType
                )
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        isUploading = false
        uploadProgress = nil

        // Refresh folder contents
        await loadChildren()

        // Show errors if any
        if !errors.isEmpty {
            uploadError = errors.joined(separator: "\n")
            showUploadError = true
        }
    }

    // MARK: - New Folder

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let path = folderPath.isEmpty ? name : "\(folderPath)/\(name)"

        do {
            let _: SuccessResponse = try await APIClient.shared.library.createFolder(path: path)
            await loadChildren()
        } catch {
            uploadError = "Failed to create folder: \(error.localizedDescription)"
            showUploadError = true
        }
    }
}
