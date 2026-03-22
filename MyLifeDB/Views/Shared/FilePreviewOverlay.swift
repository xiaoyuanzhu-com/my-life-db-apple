//
//  FilePreviewOverlay.swift
//  MyLifeDB
//
//  Unified overlay that wraps any file preview content with consistent
//  toolbar controls (close, share, menu). Replaces the split toolbar
//  experience where non-media files had buttons and media files had
//  tap-to-dismiss only.
//
//  For media files: toolbar starts visible, single-tap toggles visibility,
//  drag-down dismisses.
//  For non-media files: toolbar always visible, no drag-down, no tap-to-toggle.
//

import SwiftUI
#if os(iOS)
import Photos
import UniformTypeIdentifiers
#endif

struct FilePreviewOverlay<Content: View>: View {

    // MARK: - Properties

    let filePath: String
    let fileName: String
    let file: FileRecord?
    let isMedia: Bool
    let onDismiss: () -> Void
    let content: (@escaping () -> Void) -> Content

    @State private var toolbarVisible = true
    @State private var isDownloadingForShare = false
    @State private var isDownloadingForSave = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var refreshID = UUID()

    #if os(iOS)
    @State private var dragOffset: CGFloat = 0
    #endif

    // MARK: - Drag Gesture Constants

    /// Minimum drag before recognizing a vertical swipe.
    private let dragMinDistance: CGFloat = 20
    /// Ratio: vertical must exceed horizontal × this factor to qualify as a dismiss drag.
    private let dragDirectionRatio: CGFloat = 1.5
    /// Distance threshold for committing a dismiss (points).
    private let dragDismissThreshold: CGFloat = 100
    /// Predicted velocity threshold for committing a dismiss (points).
    private let dragVelocityThreshold: CGFloat = 300
    /// Off-screen offset to animate toward during dismiss.
    private let dragDismissOffset: CGFloat = 600

    // MARK: - Initializer

    /// Create a file preview overlay.
    /// - Parameters:
    ///   - filePath: Server path to the file.
    ///   - fileName: Display name of the file.
    ///   - file: Optional resolved FileRecord (used to determine media type).
    ///   - isMedia: Whether the file is image/video (enables tap-to-toggle toolbar, drag-to-dismiss).
    ///   - onDismiss: Called when the user closes the preview.
    ///   - content: Builder that receives a `toggleToolbar` closure for child views to call on single-tap.
    init(
        filePath: String,
        fileName: String,
        file: FileRecord? = nil,
        isMedia: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> Content
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.file = file
        self.isMedia = isMedia
        self.onDismiss = onDismiss
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            contentLayer
                .id(refreshID)
            if toolbarVisible {
                toolbarLayer
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toolbarVisible)
        .alert("Delete File", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \"\(fileName)\"? This cannot be undone.")
        }
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteError ?? "Unknown error")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    // MARK: - Content Layer

    @ViewBuilder
    private var contentLayer: some View {
        #if os(iOS)
        if isMedia {
            content(toggleToolbar)
                .offset(y: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: dragMinDistance)
                        .onChanged { value in
                            // Only track downward vertical drags (not horizontal swipes)
                            let vertical = value.translation.height
                            let horizontal = abs(value.translation.width)
                            guard vertical > 0, vertical > horizontal * dragDirectionRatio else { return }
                            dragOffset = vertical
                        }
                        .onEnded { value in
                            guard dragOffset > 0 else { return }
                            let vertical = value.translation.height
                            let velocity = value.predictedEndTranslation.height
                            if vertical > dragDismissThreshold || velocity > dragVelocityThreshold {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragOffset = dragDismissOffset
                                } completion: {
                                    onDismiss()
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        } else {
            content(toggleToolbar)
        }
        #else
        content(toggleToolbar)
        #endif
    }

    // MARK: - Toolbar Layer

    private var toolbarLayer: some View {
        VStack {
            HStack {
                // Close button — top left
                GlassCircleButton(systemName: "xmark") {
                    onDismiss()
                }
                .padding(.leading, 16)

                Spacer()

                // Menu button — top right
                HStack(spacing: 8) {
                    if isDownloadingForShare || isDownloadingForSave {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    }

                    Menu {
                        Button {
                            performShare()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            performDownload()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }

                        Divider()

                        Button {
                            forceRefresh()
                        } label: {
                            Label("Refresh from Server", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        GlassCircleButton(systemName: "ellipsis") { }
                            .allowsHitTesting(false)
                    }
                }
                .padding(.trailing, 16)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Toolbar Toggle

    private func toggleToolbar() {
        guard isMedia else { return }
        toolbarVisible.toggle()
    }

    // MARK: - Force Refresh

    private func forceRefresh() {
        let url = APIClient.shared.rawFileURL(path: filePath)
        FileCache.shared.invalidate(for: url)
        refreshID = UUID()
    }

    // MARK: - Share

    private func performShare() {
        guard !isDownloadingForShare else { return }
        isDownloadingForShare = true
        Task {
            defer { isDownloadingForShare = false }
            do {
                let data = try await APIClient.shared.getRawFile(path: filePath)
                // Use a unique subdirectory so concurrent shares don't collide,
                // and schedule cleanup after a delay to give the share sheet time.
                let shareDir = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: shareDir, withIntermediateDirectories: true)
                let tempURL = shareDir.appendingPathComponent(fileName)
                try data.write(to: tempURL)
                presentShareSheet(items: [tempURL])
                // Clean up after 60 seconds — share sheet retains the file briefly.
                Task {
                    try? await Task.sleep(for: .seconds(60))
                    try? FileManager.default.removeItem(at: shareDir)
                }
            } catch {
                print("[FilePreviewOverlay] Failed to download file for sharing: \(error)")
            }
        }
    }

    // MARK: - Download / Save

    private func performDownload() {
        guard !isDownloadingForSave else { return }
        isDownloadingForSave = true
        Task {
            defer { isDownloadingForSave = false }
            do {
                let data = try await APIClient.shared.getRawFile(path: filePath)
                let isImageOrVideo = file?.isImage == true || file?.isVideo == true
                #if os(iOS)
                if isImageOrVideo {
                    try await saveToPhotos(data: data)
                } else {
                    try saveToFiles(data: data)
                }
                #elseif os(macOS)
                try await saveWithPanel(data: data)
                #endif
            } catch {
                saveError = error.localizedDescription
                showSaveError = true
            }
        }
    }

    // MARK: - Platform Save Helpers

    #if os(iOS)
    private func saveToPhotos(data: Data) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)

        try await PHPhotoLibrary.shared().performChanges {
            if file?.isVideo == true {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
            }
        }
        try? FileManager.default.removeItem(at: tempURL)
    }

    @MainActor
    private func saveToFiles(data: Data) throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: tempURL)

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var topVC = scene.keyWindow?.rootViewController else { return }
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        // forExporting copies the file, so the original temp file can be cleaned up.
        let picker = UIDocumentPickerViewController(forExporting: [tempURL])
        picker.shouldShowFileExtensions = true
        topVC.present(picker, animated: true)
    }
    #endif

    #if os(macOS)
    @MainActor
    private func saveWithPanel(data: Data) async throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            let response = await panel.beginSheetModal(for: window)
            if response == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } else {
            // No window available — present as a standalone modal
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    try? data.write(to: url)
                }
            }
        }
    }
    #endif

    // MARK: - Delete

    private func performDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await APIClient.shared.library.delete(path: filePath)
                onDismiss()
            } catch {
                deleteError = error.localizedDescription
                showDeleteError = true
            }
        }
    }
}
