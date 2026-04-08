//
//  ExploreView.swift
//  MyLifeDB
//
//  Root view for the Explore tab. Displays a masonry feed of
//  agent-published posts with cursor-based pagination.
//

import SwiftUI

struct ExploreView: View {

    @State private var posts: [ExplorePost] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var hasMoreOlder = false
    @State private var lastCursor: String?
    @State private var loadingMore = false
    @State private var selectedPost: ExplorePost?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && posts.isEmpty {
                    loadingView
                } else if let error, posts.isEmpty {
                    errorView(error)
                } else if posts.isEmpty {
                    emptyView
                } else {
                    feedView
                }
            }
            .navigationTitle("Explore")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .task {
            if posts.isEmpty {
                await loadPosts()
            }
        }
        .sheet(item: $selectedPost) { post in
            ExplorePostDetailView(postId: post.id)
        }
    }

    // MARK: - Feed

    private var feedView: some View {
        ScrollView {
            ExploreMasonryGrid(posts: posts, onPostTap: { post in
                selectedPost = post
            })
            .padding(.horizontal)

            if loadingMore {
                ProgressView()
                    .padding()
            }

            if hasMoreOlder {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await loadMore() }
                    }
            }
        }
        .refreshable {
            await loadPosts(ignoreCache: true)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading posts...")
            Spacer()
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Failed to load posts")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await loadPosts() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "safari")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No posts yet")
                .font(.headline)
            Text("Posts will appear here when agents publish them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadPosts(ignoreCache: Bool = false) async {
        if posts.isEmpty { isLoading = true }
        error = nil

        do {
            let response = try await APIClient.shared.explore.list(
                limit: 30,
                ignoreCache: ignoreCache
            )
            posts = response.items
            hasMoreOlder = response.hasMore.older
            lastCursor = response.cursors.last
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func loadMore() async {
        guard !loadingMore, hasMoreOlder, let cursor = lastCursor else { return }
        loadingMore = true

        do {
            let response = try await APIClient.shared.explore.fetchOlder(
                cursor: cursor
            )
            posts.append(contentsOf: response.items)
            hasMoreOlder = response.hasMore.older
            lastCursor = response.cursors.last
        } catch {
            // Silently fail for pagination
        }

        loadingMore = false
    }
}
