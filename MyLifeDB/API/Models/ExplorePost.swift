//
//  ExplorePost.swift
//  MyLifeDB
//
//  Explore post model matching backend ExplorePost.
//

import Foundation

/// Represents a post in the Explore feed
struct ExplorePost: Codable, Identifiable, Hashable {

    let id: String
    let author: String
    let title: String
    let content: String?
    let mediaType: String?
    let mediaPaths: [String]?
    let mediaDir: String?
    let tags: [String]?
    let createdAt: Int64

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ExplorePost, rhs: ExplorePost) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    var isImage: Bool { mediaType == "image" }
    var isVideo: Bool { mediaType == "video" }
    var hasMedia: Bool { !(mediaPaths ?? []).isEmpty }
    var imageCount: Int { mediaPaths?.count ?? 0 }
    var coverImagePath: String? { mediaPaths?.first }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdDate, relativeTo: Date())
    }
}

/// Represents a comment on an explore post
struct ExploreComment: Codable, Identifiable {

    let id: String
    let postId: String
    let author: String
    let content: String
    let createdAt: Int64

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

/// Post with its comments (from GET /api/explore/posts/:id)
struct ExplorePostWithComments: Codable {
    let id: String
    let author: String
    let title: String
    let content: String?
    let mediaType: String?
    let mediaPaths: [String]?
    let mediaDir: String?
    let tags: [String]?
    let createdAt: Int64
    let comments: [ExploreComment]

    var post: ExplorePost {
        ExplorePost(
            id: id,
            author: author,
            title: title,
            content: content,
            mediaType: mediaType,
            mediaPaths: mediaPaths,
            mediaDir: mediaDir,
            tags: tags,
            createdAt: createdAt
        )
    }
}

// MARK: - API Response Types

/// Response from GET /api/explore/posts
struct ExplorePostsResponse: Codable {
    let items: [ExplorePost]
    let cursors: ExploreCursors
    let hasMore: ExploreHasMore
}

struct ExploreCursors: Codable {
    let first: String?
    let last: String?
}

struct ExploreHasMore: Codable {
    let older: Bool
    let newer: Bool
}
