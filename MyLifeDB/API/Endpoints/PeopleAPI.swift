//
//  PeopleAPI.swift
//  MyLifeDB
//
//  People API endpoints.
//
//  Endpoints:
//  - GET    /api/people           - List all people
//  - POST   /api/people           - Create person
//  - GET    /api/people/:id       - Get person
//  - PUT    /api/people/:id       - Update person
//  - DELETE /api/people/:id       - Delete person
//  - POST   /api/people/:id/merge - Merge two people
//  - POST   /api/people/embeddings/:id/assign   - Assign embedding
//  - POST   /api/people/embeddings/:id/unassign - Unassign embedding
//

import Foundation

/// API endpoints for people management
struct PeopleAPI {

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - List Operations

    /// List all people
    func list() async throws -> [Person] {
        try await client.request(path: "/api/people")
    }

    // MARK: - CRUD Operations

    /// Get a person by ID
    func get(id: String) async throws -> Person {
        try await client.request(path: "/api/people/\(id)")
    }

    /// Create a new person
    func create(displayName: String) async throws -> Person {
        try await client.request(
            path: "/api/people",
            method: .post,
            body: CreatePersonRequest(displayName: displayName)
        )
    }

    /// Update a person's display name
    func update(id: String, displayName: String) async throws {
        try await client.requestVoid(
            path: "/api/people/\(id)",
            method: .put,
            body: UpdatePersonRequest(displayName: displayName)
        )
    }

    /// Delete a person
    func delete(id: String) async throws {
        try await client.requestVoid(
            path: "/api/people/\(id)",
            method: .delete
        )
    }

    // MARK: - Merge Operations

    /// Merge one person into another
    /// - Parameters:
    ///   - targetId: The person to merge into (will remain)
    ///   - sourceId: The person to merge from (will be deleted)
    func merge(targetId: String, sourceId: String) async throws {
        try await client.requestVoid(
            path: "/api/people/\(targetId)/merge",
            method: .post,
            body: MergePersonRequest(sourceId: sourceId)
        )
    }

    // MARK: - Embedding Operations

    /// Assign an embedding to a person
    func assignEmbedding(embeddingId: String, to personId: String) async throws {
        try await client.requestVoid(
            path: "/api/people/embeddings/\(embeddingId)/assign",
            method: .post,
            body: AssignEmbeddingRequest(personId: personId)
        )
    }

    /// Unassign an embedding from its person
    func unassignEmbedding(embeddingId: String) async throws {
        try await client.requestVoid(
            path: "/api/people/embeddings/\(embeddingId)/unassign",
            method: .post
        )
    }
}
