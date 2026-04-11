//
//  ExplorePostDetailView.swift
//  MyLifeDB
//
//  Detail view for a single Explore post.
//  Shows image carousel, full content, tags, and comments.
//

import SwiftUI

struct ExplorePostDetailView: View {

    let postId: String

    @State private var postData: ExplorePostWithComments?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var currentImageIndex = 0

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
    }

    // MARK: - Content

    private func contentView(_ data: ExplorePostWithComments) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Media
                mediaSection(data)

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

                        Text("Comments (\(data.comments.count))")
                            .font(.headline)

                        ForEach(data.comments) { comment in
                            commentRow(comment)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Media

    @ViewBuilder
    private func mediaSection(_ data: ExplorePostWithComments) -> some View {
        let paths = data.mediaPaths ?? []
        if !paths.isEmpty {
            if data.mediaType == "video" {
                // Video — show placeholder with play icon since we can't inline play easily
                ZStack {
                    AuthenticatedImage(path: paths[0])
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
            } else if paths.count == 1 {
                AuthenticatedImage(path: paths[0])
            } else {
                // Image carousel
                TabView(selection: $currentImageIndex) {
                    ForEach(paths.indices, id: \.self) { index in
                        AuthenticatedImage(path: paths[index])
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                #endif
                .frame(minHeight: 300)
            }
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
