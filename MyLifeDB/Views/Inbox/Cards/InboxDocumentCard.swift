//
//  InboxDocumentCard.swift
//  MyLifeDB
//
//  Card component for displaying document items (PDF, Office docs).
//

import SwiftUI

struct InboxDocumentCard: View {
    let item: InboxItem

    var body: some View {
        VStack(spacing: 8) {
            if let screenshotPath = item.screenshotSqlar {
                AuthenticatedSqlarImage(path: screenshotPath)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                documentIconView
            }

            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: 240)
    }

    private var documentIconView: some View {
        VStack(spacing: 8) {
            Image(systemName: documentIcon)
                .font(.system(size: 48))
                .foregroundStyle(documentColor)

            Text(fileExtension.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 100)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var documentIcon: String {
        switch fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "slider.horizontal.below.rectangle"
        default: return "doc.fill"
        }
    }

    private var documentColor: Color {
        switch fileExtension {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "ppt", "pptx": return .orange
        default: return .gray
        }
    }

    private var fileExtension: String {
        guard let dotIndex = item.name.lastIndex(of: ".") else { return "" }
        return String(item.name[item.name.index(after: dotIndex)...]).lowercased()
    }
}
