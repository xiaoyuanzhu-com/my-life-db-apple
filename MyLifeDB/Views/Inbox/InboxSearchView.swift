//
//  InboxSearchView.swift
//  MyLifeDB
//
//  Search results view for inbox full-text keyword search.
//  Displays results as cards similar to the feed, with
//  match snippet context below each result.
//

import SwiftUI

struct InboxSearchView: View {

    let query: String

    @State private var results: [SearchResultItem] = []
    @State private var isSearching = false
    @State private var pagination: SearchPagination?
    @State private var searchError: Error?

    var body: some View {
        Group {
            if isSearching && results.isEmpty {
                loadingView
            } else if let error = searchError, results.isEmpty {
                errorView(error)
            } else if results.isEmpty && !isSearching {
                emptyView
            } else {
                resultsList
            }
        }
        .onChange(of: query) { _, newQuery in
            Task { await performSearch(query: newQuery, reset: true) }
        }
        .task {
            if results.isEmpty && !query.isEmpty {
                await performSearch(query: query, reset: true)
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 16) {
                ForEach(results) { result in
                    resultView(for: result)
                }

                // Load more
                if let pagination = pagination, pagination.hasMore {
                    ProgressView()
                        .padding(.vertical, 16)
                        .task {
                            await loadMore()
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func resultView(for result: SearchResultItem) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            InboxTimestampView(dateString: result.createdAt)

            NavigationLink(value: InboxDestination.file(path: result.path, name: result.name)) {
                resultCard(for: result)
            }
            .buttonStyle(.plain)

            // Match snippet context
            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func resultCard(for result: SearchResultItem) -> some View {
        // Create a minimal InboxItem-like card display
        Group {
            if result.isImage {
                imageResultCard(result)
            } else if let preview = result.textPreview, !preview.isEmpty {
                textResultCard(result, preview: preview)
            } else {
                fallbackResultCard(result)
            }
        }
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func textResultCard(_ result: SearchResultItem, preview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview)
                .font(.body)
                .lineLimit(10)
                .foregroundStyle(.primary)

            HStack {
                Text(result.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let size = result.formattedSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func imageResultCard(_ result: SearchResultItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: APIClient.shared.rawFileURL(path: result.path)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 200, height: 150)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                @unknown default:
                    EmptyView()
                }
            }

            Text(result.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: 344, alignment: .leading)
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
        .frame(maxWidth: 320)
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

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Search Failed")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView.search(text: query)
    }

    // MARK: - Data

    private func performSearch(query: String, reset: Bool) async {
        guard query.count >= 2 else {
            results = []
            pagination = nil
            return
        }

        if reset {
            isSearching = true
            searchError = nil
        }

        do {
            let response = try await APIClient.shared.search.search(
                query: query,
                limit: 20,
                offset: reset ? 0 : (pagination?.offset ?? 0) + (pagination?.limit ?? 20)
            )

            if reset {
                results = response.results
            } else {
                results.append(contentsOf: response.results)
            }
            pagination = response.pagination
        } catch {
            if reset {
                searchError = error
            }
        }

        isSearching = false
    }

    private func loadMore() async {
        await performSearch(query: query, reset: false)
    }
}
