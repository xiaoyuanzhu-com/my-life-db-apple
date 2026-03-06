//
//  ClaudeCodeCollector.swift
//  MyLifeDB
//
//  Collects Claude Code session files from ~/.claude/projects/ and
//  uploads them to the backend as raw imported data. macOS only.
//
//  Source: ~/.claude/projects/{project-dir}/{session-id}.jsonl
//  Dest:   imports/claude-code/{project-dir}/{session-id}.jsonl
//
//  Files are copied byte-for-byte — no transformation.
//

#if os(macOS)
import Foundation

final class ClaudeCodeCollector: DataCollector {

    let id = "claude-code"
    let displayName = "Claude Code"

    let sourceIDs: [String] = ["claude_sessions"]

    // MARK: - Source Directory

    private var sourceDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        // No special authorization needed — just filesystem access
        return FileManager.default.isReadableFile(atPath: sourceDir.path)
    }

    func authorizationStatus() -> CollectorAuthStatus {
        if !FileManager.default.fileExists(atPath: sourceDir.path) {
            return .unavailable
        }
        if FileManager.default.isReadableFile(atPath: sourceDir.path) {
            return .authorized
        }
        return .denied
    }

    // MARK: - Collection

    func collectNewSamples(fullSync: Bool) async throws -> CollectionResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceDir.path) else {
            return CollectionResult(batches: [], stats: CollectionStats(
                typesQueried: 1, typesWithData: 0, samplesCollected: 0
            ))
        }

        var batches: [DaySamples] = []
        var filesFound = 0

        // Walk the source directory
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return CollectionResult(batches: [], stats: CollectionStats(
                typesQueried: 1, typesWithData: 0, samplesCollected: 0
            ))
        }

        for projectURL in projectDirs {
            guard isDirectory(projectURL) else { continue }
            let projectName = projectURL.lastPathComponent

            // Collect files in this project directory
            let projectBatches = try collectProject(
                projectURL: projectURL,
                projectName: projectName
            )
            batches.append(contentsOf: projectBatches)
            filesFound += projectBatches.count
        }

        return CollectionResult(
            batches: batches,
            stats: CollectionStats(
                typesQueried: 1,
                typesWithData: filesFound > 0 ? 1 : 0,
                samplesCollected: filesFound
            )
        )
    }

    func commitAnchor(for batch: DaySamples) async {
        // No anchor needed — we use watermark-based dedup in SyncManager
    }

    // MARK: - Private Helpers

    private func collectProject(
        projectURL: URL,
        projectName: String
    ) throws -> [DaySamples] {
        let fm = FileManager.default
        var batches: [DaySamples] = []

        // Enumerate all files recursively in this project directory
        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard isRegularFile(fileURL) else { continue }
            guard shouldSync(fileURL.lastPathComponent) else { continue }

            // Read file data
            guard let data = try? Data(contentsOf: fileURL) else { continue }

            // Compute upload path: imports/claude-code/{projectName}/{relative-path}
            let relativePath = fileURL.path.replacingOccurrences(
                of: projectURL.path + "/", with: ""
            )
            let uploadPath = "imports/claude-code/\(projectName)/\(relativePath)"

            // Use file modification date for the batch date
            let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

            batches.append(DaySamples(
                date: modDate,
                collectorID: id,
                uploadPath: uploadPath,
                data: data,
                anchorToken: nil
            ))
        }

        return batches
    }

    private func shouldSync(_ filename: String) -> Bool {
        if filename == "sessions-index.json" { return true }
        return filename.hasSuffix(".jsonl")
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }
}
#endif // os(macOS)
