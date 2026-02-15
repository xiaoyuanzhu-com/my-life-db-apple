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
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let size = item.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            Spacer(minLength: 8)

            Image(systemName: documentIcon)
                .font(.title2)
                .foregroundStyle(documentColor)
        }
        .frame(maxWidth: 320)
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
