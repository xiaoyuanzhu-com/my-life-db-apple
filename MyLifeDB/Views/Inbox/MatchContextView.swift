//
//  MatchContextView.swift
//  MyLifeDB
//
//  Displays search match context below card content.
//  Handles both semantic and keyword/digest matches.
//  Matches web implementation in match-context.tsx.
//

import SwiftUI

struct MatchContextView: View {
    let context: MatchContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            snippetView
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if context.source == "semantic" {
            semanticHeader
        } else {
            digestHeader
        }
    }

    private var semanticHeader: some View {
        HStack(spacing: 0) {
            Text("Semantic match")
            if let score = context.score {
                Text(" (\(Int(score * 100))% similar)")
            }
            if let sourceType = context.sourceType {
                Text(" · \(sourceType)")
            }
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    }

    private var digestHeader: some View {
        Text("Matched in \(context.digest?.label ?? "content")")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    // MARK: - Snippet

    @ViewBuilder
    private var snippetView: some View {
        if context.source == "semantic" {
            Text(context.snippet)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .italic()
        } else {
            highlightedSnippet(context.snippet)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }

    /// Parse Meilisearch `<em>` tags and render highlighted text.
    private func highlightedSnippet(_ snippet: String) -> Text {
        var result = Text("")
        let parts = snippet.components(separatedBy: "<em>")

        for (i, part) in parts.enumerated() {
            if i == 0 {
                // First part is always plain text (before any <em>)
                result = result + Text(part)
            } else {
                // Split on </em> to get highlighted vs plain
                let subparts = part.components(separatedBy: "</em>")
                if subparts.count >= 2 {
                    let highlighted = subparts[0]
                    let plain = subparts[1...].joined(separator: "</em>")
                    result = result
                        + Text(highlighted)
                            .foregroundColor(.primary)
                            .bold()
                            .underline()
                        + Text(plain)
                } else {
                    // No closing tag, treat as plain
                    result = result + Text(part)
                }
            }
        }

        return result
    }
}
