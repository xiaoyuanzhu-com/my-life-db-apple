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
            Text(trimAroundMatch(context.snippet))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .italic()
                .lineLimit(2)
        } else {
            Text(highlightedSnippet(context.snippet))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)
        }
    }

    // MARK: - Snippet Trimming

    /// Trim plain text to ~80 chars around the middle, adding ellipsis.
    private func trimAroundMatch(_ text: String) -> String {
        let maxChars = 80
        guard text.count > maxChars else { return text }
        let center = text.count / 2
        let half = maxChars / 2
        let start = max(0, center - half)
        let end = min(text.count, center + half)
        let startIdx = text.index(text.startIndex, offsetBy: start)
        let endIdx = text.index(text.startIndex, offsetBy: end)
        let prefix = start > 0 ? "…" : ""
        let suffix = end < text.count ? "…" : ""
        return "\(prefix)\(text[startIdx..<endIdx])\(suffix)"
    }

    /// Trim snippet to show context around first `<em>` match, then parse highlights.
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        let trimmed = trimAroundEmMatch(snippet)
        return parseEmTags(trimmed)
    }

    /// Trim raw snippet (with `<em>` tags) to ~80 chars of plain text around the first match.
    private func trimAroundEmMatch(_ snippet: String) -> String {
        let maxChars = 80

        // Strip tags to measure plain text length
        let plain = snippet
            .replacingOccurrences(of: "<em>", with: "")
            .replacingOccurrences(of: "</em>", with: "")
        guard plain.count > maxChars else { return snippet }

        // Find first <em> position in plain text
        let beforeFirstEm = snippet.components(separatedBy: "<em>").first ?? ""
        let matchStart = beforeFirstEm
            .replacingOccurrences(of: "</em>", with: "")
            .count

        // Window centered on match
        let half = maxChars / 2
        let windowStart = max(0, matchStart - half)
        let windowEnd = min(plain.count, matchStart + half)

        // Map plain-text offsets back to the raw snippet (with tags)
        var plainIdx = 0
        var rawStart: String.Index?
        var rawEnd: String.Index?
        var i = snippet.startIndex

        while i < snippet.endIndex {
            // Skip over tags
            if snippet[i...].hasPrefix("<em>") {
                i = snippet.index(i, offsetBy: 4)
                continue
            }
            if snippet[i...].hasPrefix("</em>") {
                i = snippet.index(i, offsetBy: 5)
                continue
            }
            if plainIdx == windowStart { rawStart = i }
            plainIdx += 1
            if plainIdx == windowEnd { rawEnd = snippet.index(after: i); break }
            i = snippet.index(after: i)
        }

        let start = rawStart ?? snippet.startIndex
        let end = rawEnd ?? snippet.endIndex

        // Collect the substring, preserving any tag that's partially inside
        var result = String(snippet[start..<end])

        // Fix unclosed tags at boundaries
        let openCount = result.components(separatedBy: "<em>").count - 1
        let closeCount = result.components(separatedBy: "</em>").count - 1
        if openCount > closeCount {
            result += "</em>"
        } else if closeCount > openCount {
            result = "<em>" + result
        }

        let prefix = windowStart > 0 ? "…" : ""
        let suffix = windowEnd < plain.count ? "…" : ""
        return "\(prefix)\(result)\(suffix)"
    }

    /// Parse Meilisearch `<em>` tags into an AttributedString with yellow background highlights.
    private func parseEmTags(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        let parts = snippet.components(separatedBy: "<em>")

        for (i, part) in parts.enumerated() {
            if i == 0 {
                result += AttributedString(part)
            } else {
                let subparts = part.components(separatedBy: "</em>")
                if subparts.count >= 2 {
                    var highlighted = AttributedString(subparts[0])
                    highlighted.backgroundColor = .yellow.opacity(0.3)
                    highlighted.foregroundColor = .primary
                    result += highlighted
                    result += AttributedString(subparts[1...].joined(separator: "</em>"))
                } else {
                    result += AttributedString(part)
                }
            }
        }

        return result
    }
}
