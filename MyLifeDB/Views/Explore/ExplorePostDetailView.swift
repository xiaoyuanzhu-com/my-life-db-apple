//
//  ExplorePostDetailView.swift
//  MyLifeDB
//
//  Detail view for a single Explore post.
//  Shows image carousel, full content, tags, and comments.
//  iPad/Mac: side-by-side layout (images left, text right).
//  iPhone: stacked layout.
//

import SwiftUI

struct ExplorePostDetailView: View {

    let postId: String

    @State private var postData: ExplorePostWithComments?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var currentImageIndex = 0
    @State private var showFullscreen = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading post...")
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let data = postData {
                contentView(data)
            }
        }
        .navigationTitle("Post")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadPost()
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            if let paths = postData?.mediaPaths, !paths.isEmpty {
                ImageFullscreenView(
                    images: paths,
                    initialIndex: currentImageIndex,
                    onDismiss: { showFullscreen = false }
                )
            }
        }
    }

    // MARK: - Content

    private func contentView(_ data: ExplorePostWithComments) -> some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad/Mac: side-by-side layout
                HStack(spacing: 0) {
                    if let paths = data.mediaPaths, !paths.isEmpty {
                        mediaSectionWide(data, paths: paths)
                            .frame(maxWidth: .infinity)
                    }
                    ScrollView {
                        textContent(data)
                    }
                    .frame(width: 380)
                }
            } else {
                // iPhone: stacked layout
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        mediaSection(data)
                        textContent(data)
                    }
                }
            }
        }
    }

    // MARK: - Text Content

    private func textContent(_ data: ExplorePostWithComments) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(data.title)
                .font(.title2)
                .fontWeight(.bold)

            // Author + date
            HStack {
                Label(data.author, systemImage: "person.circle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(data.post.formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Content
            if let content = data.content, !content.isEmpty {
                Text(content)
                    .font(.body)
            }

            // Tags
            if let tags = data.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            // Comments
            if !data.comments.isEmpty {
                Divider()

                Text(String(localized: "Comments (\(data.comments.count))"))
                    .font(.headline)

                ForEach(data.comments) { comment in
                    commentRow(comment)
                }
            }
        }
        .padding()
    }

    // MARK: - Media (iPhone stacked)

    @ViewBuilder
    private func mediaSection(_ data: ExplorePostWithComments) -> some View {
        let paths = data.mediaPaths ?? []
        if !paths.isEmpty {
            if data.mediaType == "video" {
                videoPlaceholder(paths[0])
            } else {
                VStack(spacing: 0) {
                    imageCarousel(paths: paths)
                    indicators(count: paths.count)
                }
            }
        }
    }

    // MARK: - Media (iPad/Mac wide)

    @ViewBuilder
    private func mediaSectionWide(_ data: ExplorePostWithComments, paths: [String]) -> some View {
        if data.mediaType == "video" {
            videoPlaceholder(paths[0])
        } else {
            VStack(spacing: 0) {
                Spacer()
                imageCarousel(paths: paths)
                indicators(count: paths.count)
                Spacer()
            }
            .background(Color.secondary.opacity(0.05))
        }
    }

    // MARK: - Image Carousel

    @ViewBuilder
    private func imageCarousel(paths: [String]) -> some View {
        ZStack(alignment: .topTrailing) {
            if paths.count == 1 {
                AuthenticatedImage(path: paths[0])
                    .onTapGesture { showFullscreen = true }
            } else {
                TabView(selection: $currentImageIndex) {
                    ForEach(paths.indices, id: \.self) { index in
                        AuthenticatedImage(path: paths[index])
                            .tag(index)
                            .onTapGesture { showFullscreen = true }
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .frame(minHeight: 300)
            }

            // [current]/[total] counter
            if paths.count > 1 {
                Text("\(currentImageIndex + 1)/\(paths.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }

    // MARK: - Dot Indicators (below images)

    @ViewBuilder
    private func indicators(count: Int) -> some View {
        if count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(index == currentImageIndex ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Video Placeholder

    private func videoPlaceholder(_ path: String) -> some View {
        ZStack {
            AuthenticatedImage(path: path)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white)
                .shadow(radius: 6)
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: ExploreComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(comment.createdDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(comment.content)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadPost() async {
        isLoading = true
        error = nil

        do {
            postData = try await APIClient.shared.explore.get(id: postId)
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
