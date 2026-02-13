//
//  TextFileView.swift
//  MyLifeDB
//
//  Native text/code file viewer.
//  Displays file content with monospace font and text selection support.
//

import SwiftUI

struct TextFileView: View {

    let path: String

    @State private var content: String?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if let content = content {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if isLoading {
                ProgressView("Loading file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Failed to Load File",
                    systemImage: "doc.plaintext",
                    description: Text(error?.localizedDescription ?? "Unknown error")
                )
            }
        }
        .task {
            await loadContent()
        }
    }

    // MARK: - Data Fetching

    private func loadContent() async {
        isLoading = true
        error = nil

        do {
            let data = try await APIClient.shared.library.getRawContent(path: path)
            content = String(data: data, encoding: .utf8)
            if content == nil {
                // Try Latin-1 as fallback for non-UTF8 files
                content = String(data: data, encoding: .isoLatin1)
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
