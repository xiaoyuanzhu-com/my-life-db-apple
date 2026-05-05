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
    let name: String   // Display name ("january", "2024", "Data")
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

    // Search state
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFocused: Bool

    // Upload state
    @State private var showFilePicker = false
    @State private var showFolderPicker = false
    @State private var isUploading = false
    @State private var uploadProgress: (current: Int, total: Int)?
    @State private var uploadError: String?
    @State private var showUploadError = false

    // New folder state
    @State private var showNewFolderDialog = false
    @State private var newFolderName = ""

    // MARK: - Filtered Children

    private var filteredChildren: [FileTreeNode] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return children }
        return children.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSearchActive {
                searchBar
            }
            Group {
                if isLoading && children.isEmpty {
                    loadingView
                } else if let error = error, children.isEmpty {
                    errorView(error)
                } else if filteredChildren.isEmpty && !isLoading {
                    emptyView
                } else {
                    contentView
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isSearchActive)
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
                        Label(ancestor.name, systemImage: ancestor.depth == 0 ? "tray.full" : "folder")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        isSearchActive = true
                        isSearchFocused = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Upload File", systemImage: "arrow.up.doc")
                    }
                    .disabled(isUploading)

                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Upload Folder", systemImage: "arrow.up.doc.on.clipboard")
                    }
                    .disabled(isUploading)

                    Button {
                        newFolderName = ""
                        showNewFolderDialog = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        Task { await loadChildren(ignoreCache: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
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
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
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
                // Render cached snapshot synchronously so the user sees the
                // last-known folder contents immediately, with no spinner.
                if let cached = LibraryTreeCache.shared.snapshot(for: folderPath) {
                    children = cached.children
                }
                // Always refresh in the background. The fetch updates `children`
                // (and the on-disk snapshot) only if the response differs.
                await loadChildren()
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .grid:
            LibraryGridView(children: filteredChildren, folderPath: folderPath)
        case .list:
            LibraryListView(children: filteredChildren, folderPath: folderPath)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("Search files...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                searchText = ""
                isSearchFocused = false
                isSearchActive = false
            }
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformGray6)
        .transition(.move(edge: .top).combined(with: .opacity))
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
        // Only show loading indicator on initial load (no data yet).
        // During pull-to-refresh, .refreshable handles its own spinner;
        // setting isLoading here would cause unnecessary state churn that
        // can interrupt the refresh gesture on ScrollView.
        if children.isEmpty {
            isLoading = true
        }
        error = nil

        do {
            let response = try await APIClient.shared.library.getTree(path: folderPath, depth: 1, ignoreCache: ignoreCache)
            // Avoid pointlessly reassigning when nothing changed — keeps the
            // SwiftUI diff trivial when the snapshot already matched the
            // server's response.
            if response.children != children {
                children = response.children
            }
            LibraryTreeCache.shared.save(response, for: folderPath)
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

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            Task { await uploadFolder(folderURL) }
        case .failure(let error):
            uploadError = error.localizedDescription
            showUploadError = true
        }
    }

    private func uploadFolder(_ folderURL: URL) async {
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

        // Recursively enumerate regular files inside the picked folder.
        var files: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let next = enumerator.nextObject() {
                guard let url = next as? URL else { continue }
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                if isRegular { files.append(url) }
            }
        }

        guard !files.isEmpty else { return }

        isUploading = true
        uploadProgress = (current: 0, total: files.count)

        var errors: [String] = []
        let rootName = folderURL.lastPathComponent
        let rootPath = folderURL.standardizedFileURL.path

        for (index, fileURL) in files.enumerated() {
            uploadProgress = (current: index + 1, total: files.count)

            do {
                let data = try Data(contentsOf: fileURL)
                let filename = fileURL.lastPathComponent

                // Relative directory inside the picked folder, e.g. "sub/a" for "<root>/sub/a/file.txt".
                let fileDirPath = fileURL.deletingLastPathComponent().standardizedFileURL.path
                var relativeDir = fileDirPath
                if relativeDir.hasPrefix(rootPath) {
                    relativeDir.removeFirst(rootPath.count)
                }
                relativeDir = relativeDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                // Include the picked folder itself as the top-level destination dir.
                let subPath = relativeDir.isEmpty ? rootName : "\(rootName)/\(relativeDir)"
                let destination = folderPath.isEmpty ? subPath : "\(folderPath)/\(subPath)"

                let utType = UTType(filenameExtension: fileURL.pathExtension)
                let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"

                let _: SimpleUploadResponse = try await APIClient.shared.library.simpleUpload(
                    data: data,
                    filename: filename,
                    destination: destination,
                    mimeType: mimeType
                )
            } catch {
                errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        isUploading = false
        uploadProgress = nil

        await loadChildren()

        if !errors.isEmpty {
            uploadError = errors.joined(separator: "\n")
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
    ///   [("2024", "photos/2024", 2), ("photos", "photos", 1), ("Data", "", 0)]
    private var ancestorFolders: [AncestorFolder] {
        guard !folderPath.isEmpty else { return [] }

        let components = folderPath.split(separator: "/").map(String.init)
        var ancestors: [AncestorFolder] = []

        // Walk from the immediate parent down to the root
        for depth in stride(from: components.count - 1, through: 1, by: -1) {
            let path = components[0..<depth].joined(separator: "/")
            ancestors.append(AncestorFolder(name: components[depth - 1], path: path, depth: depth))
        }

        // Root ("Data")
        ancestors.append(AncestorFolder(name: "Data", path: "", depth: 0))

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
