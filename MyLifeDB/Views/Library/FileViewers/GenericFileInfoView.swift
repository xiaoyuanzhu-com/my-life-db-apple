//
//  GenericFileInfoView.swift
//  MyLifeDB
//
//  Fallback view for unsupported file types.
//  Shows file metadata (name, size, type, dates).
//

import SwiftUI

struct GenericFileInfoView: View {

    let file: FileRecord
    let filePath: String

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

                    infoRow(label: "Modified", value: file.modifiedDate.formatted(date: .long, time: .shortened))
                    infoRow(label: "Created", value: file.createdDate.formatted(date: .long, time: .shortened))
                }
                .background(Color.platformGray6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

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
