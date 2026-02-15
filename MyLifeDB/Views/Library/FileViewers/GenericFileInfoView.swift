//
//  GenericFileInfoView.swift
//  MyLifeDB
//
//  Fallback view for unsupported file types.
//  Shows file metadata (name, size, type, dates) and a share button.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GenericFileInfoView: View {

    let file: FileRecord
    let filePath: String

    @State private var isDownloading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)

                // File icon
                Image(systemName: iconName)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                // File name
                Text(file.name)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Metadata rows
                VStack(spacing: 0) {
                    if let size = file.formattedSize {
                        infoRow(label: "Size", value: size)
                    }

                    if let mime = file.mimeType {
                        infoRow(label: "Type", value: mime)
                    }

                    if let ext = file.fileExtension {
                        infoRow(label: "Extension", value: ext.uppercased())
                    }

                    if let date = file.modifiedDate {
                        infoRow(label: "Modified", value: date.formatted(date: .long, time: .shortened))
                    }

                    if let date = file.createdDate {
                        infoRow(label: "Created", value: date.formatted(date: .long, time: .shortened))
                    }
                }
                .background(Color.platformGray6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                // Share / Open in button
                Button {
                    guard !isDownloading else { return }
                    isDownloading = true
                    Task {
                        defer { isDownloading = false }
                        do {
                            let data = try await APIClient.shared.getRawFile(path: filePath)
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
                            try data.write(to: tempURL)
                            presentShareSheet(items: [tempURL])
                        } catch {
                            print("[Share] Failed to download file: \(error)")
                        }
                    }
                } label: {
                    if isDownloading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isDownloading)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var iconName: String {
        if file.isImage { return "photo" }
        if file.isVideo { return "video" }
        if file.isAudio { return "waveform" }
        if file.isPDF { return "doc.text" }
        if file.isText { return "doc.plaintext" }
        return "doc"
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
