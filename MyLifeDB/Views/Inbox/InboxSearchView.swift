//
//  InboxSearchView.swift
//  MyLifeDB
//
//  Search results view for inbox.
//  Receives results from the container (search is triggered by input bar text).
//

import SwiftUI

struct InboxSearchView: View {

    let results: [SearchResultItem]
    let isSearching: Bool

    private var maxCardWidth: CGFloat {
        #if os(iOS) || os(visionOS)
        let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        return (scene?.screen.bounds.width ?? 393) * 0.8
        #elseif os(macOS)
        return (NSScreen.main?.frame.width ?? 800) * 0.8
        #endif
    }

    var body: some View {
        Group {
            if isSearching && results.isEmpty {
                loadingView
            } else if results.isEmpty {
                emptyView
            } else {
                resultsList
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 16) {
                ForEach(results) { result in
                    resultView(for: result)
                        .frame(maxWidth: maxCardWidth)
                        .flippedForChat()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .flippedForChat()
    }

    @ViewBuilder
    private func resultView(for result: SearchResultItem) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            InboxTimestampView(dateString: result.createdAt)

            NavigationLink(value: InboxDestination.file(path: result.path, name: result.name)) {
                resultCard(for: result)
            }
            .buttonStyle(.plain)

            // Match context
            if let matchContext = result.matchContext, !matchContext.snippet.isEmpty {
                MatchContextView(context: matchContext)
            } else if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func resultCard(for result: SearchResultItem) -> some View {
        Group {
            if result.isImage {
                imageResultCard(result)
            } else if let preview = result.textPreview, !preview.isEmpty {
                textResultCard(preview: preview)
            } else {
                fallbackResultCard(result)
            }
        }
        .background(Color.platformSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func textResultCard(preview: String) -> some View {
        Text(preview)
            .font(.body)
            .lineLimit(10)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageResultCard(_ result: SearchResultItem) -> some View {
        AuthenticatedImage(path: result.path)
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(8)
    }

    private func fallbackResultCard(_ result: SearchResultItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let size = result.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView.search
    }
}

// MARK: - Flipped Layout Helper

private extension View {
    func flippedForChat() -> some View {
        scaleEffect(x: 1, y: -1)
    }
}
