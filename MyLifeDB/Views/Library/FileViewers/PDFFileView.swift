//
//  PDFFileView.swift
//  MyLifeDB
//
//  Native PDF viewer using PDFKit.
//  Fetches PDF data via authenticated API, then renders with PDFView.
//

import SwiftUI
import PDFKit

struct PDFFileView: View {

    let path: String

    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if let document = pdfDocument {
                PDFKitRepresentable(document: document)
                    .ignoresSafeArea(edges: .bottom)
            } else if isLoading {
                ProgressView("Loading PDF...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Failed to Load PDF",
                    systemImage: "doc.text",
                    description: Text(error?.localizedDescription ?? "Unknown error")
                )
            }
        }
        .task {
            await loadPDF()
        }
    }

    // MARK: - Data Fetching

    private func loadPDF() async {
        isLoading = true
        error = nil

        do {
            let data = try await APIClient.shared.library.getRawContent(path: path)
            pdfDocument = PDFDocument(data: data)
            if pdfDocument == nil {
                self.error = NSError(
                    domain: "PDFFileView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid PDF data"]
                )
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

// MARK: - PDFKit UIViewRepresentable

#if os(iOS) || os(visionOS)
private struct PDFKitRepresentable: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
#elseif os(macOS)
private struct PDFKitRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}
#endif
