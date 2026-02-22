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

// MARK: - Ancestor Folder

/// A folder in the breadcrumb hierarchy, used by the toolbar title menu.
struct AncestorFolder: Identifiable {
    let id = UUID()
    let name: String   // Display name ("january", "2024", "Library")
    let path: String   // Full relative path ("photos/2024", "photos", "")
    let depth: Int     // Depth in the navigation stack (0 = root)
}

// MARK: - LibraryFolderView

struct LibraryFolderView: View {

    let folderPath: String
    let folderName: String
    @Binding var viewMode: LibraryViewMode
    @Binding var navigationPath: NavigationPath

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
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarTitleMenu {
            if !folderPath.isEmpty {
                ForEach(ancestorFolders) { ancestor in
                    Button {
                        navigateToAncestor(ancestor)
                    } label: {
                        Label(ancestor.name, systemImage: ancestor.depth == 0 ? "books.vertical" : "folder")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Upload Files", systemImage: "arrow.up.doc")
                    }
                    .disabled(isUploading)

                    Button {
                        newFolderName = ""
                        showNewFolderDialog = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }

                    Divider()

                    Picker("View Mode", selection: $viewMode) {
                        Label("Grid", systemImage: "square.grid.2x2")
                            .tag(LibraryViewMode.grid)
                        Label("List", systemImage: "list.bullet")
                            .tag(LibraryViewMode.list)
                    }
                } label: {
                    Image(systemName: "ellipsis")
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
            await loadChildren(ignoreCache: true)
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

    private func loadChildren(ignoreCache: Bool = false) async {
        isLoading = true
        error = nil

        do {
            let response = try await APIClient.shared.library.getTree(path: folderPath, depth: 1, ignoreCache: ignoreCache)
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

    // MARK: - Folder Hierarchy Navigation

    /// Builds the ancestor chain from the immediate parent up to the root.
    /// Example: "photos/2024/january" →
    ///   [("2024", "photos/2024", 2), ("photos", "photos", 1), ("Library", "", 0)]
    private var ancestorFolders: [AncestorFolder] {
        guard !folderPath.isEmpty else { return [] }

        let components = folderPath.split(separator: "/").map(String.init)
        var ancestors: [AncestorFolder] = []

        // Walk from the immediate parent down to the root
        for depth in stride(from: components.count - 1, through: 1, by: -1) {
            let path = components[0..<depth].joined(separator: "/")
            ancestors.append(AncestorFolder(name: components[depth - 1], path: path, depth: depth))
        }

        // Root ("Library")
        ancestors.append(AncestorFolder(name: "Library", path: "", depth: 0))

        return ancestors
    }

    /// Navigate to an ancestor by popping the navigation stack to the correct depth.
    private func navigateToAncestor(_ ancestor: AncestorFolder) {
        let currentDepth = folderPath.split(separator: "/").count
        let popCount = currentDepth - ancestor.depth
        guard popCount > 0 else { return }

        if ancestor.depth == 0 {
            navigationPath = NavigationPath()
        } else {
            navigationPath.removeLast(popCount)
        }
    }
}
