//
//  Person.swift
//  MyLifeDB
//
//  Person models for people management.
//

import Foundation

/// Represents a person in the database
struct Person: Codable, Identifiable, Hashable {

    // MARK: - Properties

    let id: String
    let displayName: String
    let createdAt: String
    let updatedAt: String
    let clusters: [PersonCluster]?

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Person, rhs: Person) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    /// Number of face clusters
    var clusterCount: Int {
        clusters?.count ?? 0
    }
}

/// A face cluster associated with a person
struct PersonCluster: Codable, Identifiable {
    let id: String
    let peopleId: String?
    let clusterType: String
    let sampleCount: Int
    let createdAt: String
    let updatedAt: String
}

// MARK: - API Request/Response Types

/// Request body for POST /api/people
struct CreatePersonRequest: Codable {
    let displayName: String
}

/// Request body for PUT /api/people/:id
struct UpdatePersonRequest: Codable {
    let displayName: String
}

/// Request body for POST /api/people/:id/merge
struct MergePersonRequest: Codable {
    let sourceId: String
}

/// Request body for POST /api/people/embeddings/:id/assign
struct AssignEmbeddingRequest: Codable {
    let personId: String
}
