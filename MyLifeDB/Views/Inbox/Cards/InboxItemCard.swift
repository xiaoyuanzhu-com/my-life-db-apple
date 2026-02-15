//
//  InboxItemCard.swift
//  MyLifeDB
//
//  Card router that dispatches to the appropriate card type.
//  Borderless, frameless — content renders directly.
//

import SwiftUI

private extension View {
    func cardFrame() -> some View {
        self
            .padding(12)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct InboxItemCard: View {
    let item: InboxItem

    var body: some View {
        cardContent
    }

    @ViewBuilder
    private var cardContent: some View {
        switch contentType {
        case .image:
            InboxImageCard(item: item)
        case .video:
            InboxVideoCard(item: item)
        case .text:
            InboxTextCard(item: item)
                .cardFrame()
        case .audio:
            InboxAudioCard(item: item)
                .cardFrame()
        case .document:
            InboxDocumentCard(item: item)
                .cardFrame()
        case .fallback:
            InboxFallbackCard(item: item)
                .cardFrame()
        }
    }

    private var contentType: ContentType {
        if let mimeType = item.mimeType {
            if mimeType.hasPrefix("image/") { return .image }
            if mimeType.hasPrefix("video/") { return .video }
            if mimeType.hasPrefix("audio/") { return .audio }
            if mimeType.hasPrefix("text/") { return .text }
            if mimeType == "application/pdf" ||
               mimeType.contains("document") ||
               mimeType.contains("sheet") ||
               mimeType.contains("presentation") ||
               mimeType.contains("msword") ||
               mimeType.contains("excel") ||
               mimeType.contains("powerpoint") {
                return .document
            }
        }

        let ext = item.name.lowercased().split(separator: ".").last.map(String.init) ?? ""
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "svg":
            return .image
        case "mp4", "mov", "avi", "mkv", "webm", "m4v":
            return .video
        case "mp3", "m4a", "wav", "aac", "ogg", "flac", "wma":
            return .audio
        case "txt", "md", "markdown", "json", "xml", "html", "css", "js", "ts", "swift", "py", "go", "rs":
            return .text
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx":
            return .document
        default:
            break
        }

        if item.textPreview != nil && !(item.textPreview?.isEmpty ?? true) {
            return .text
        }

        return .fallback
    }

    private enum ContentType {
        case image, video, audio, text, document, fallback
    }
}
