//
//  FileCache.swift
//  MyLifeDB
//
//  Three-tier file cache for authenticated file access:
//  1. In-memory NSCache for raw Data (fastest, auto-evicts under memory pressure)
//  2. Disk cache in Caches/ directory (survives app restarts)
//  3. URLSession network fetch with auth headers
//
//  Also provides a decoded image convenience cache on top.
//

import Foundation
import CryptoKit
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class FileCache: @unchecked Sendable {

    #if os(iOS) || os(visionOS)
    typealias Image = UIImage
    #elseif os(macOS)
    typealias Image = NSImage
    #endif

    static let shared = FileCache()

    // MARK: - In-memory cache for raw Data

    private let dataCache = NSCache<NSString, NSData>()

    // MARK: - In-memory cache for decoded images

    private let imageCache = NSCache<NSString, Image>()

    // MARK: - Disk cache

    private let diskCacheDir: URL

    // MARK: - URLSession

    private let session: URLSession

    // MARK: - Init

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        // Raw data cache: 100 items, 80MB
        dataCache.countLimit = 100
        dataCache.totalCostLimit = 80 * 1024 * 1024

        // Decoded image cache: 150 items, 60MB
        imageCache.countLimit = 150
        imageCache.totalCostLimit = 60 * 1024 * 1024

        // Disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = cacheDir.appendingPathComponent("FileCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Public: Raw Data

    /// Fetches file data with three-tier caching:
    /// in-memory → disk → network.
    func data(for url: URL) async throws -> Data {
        let key = url.absoluteString as NSString

        // 1. Check in-memory data cache
        if let cached = dataCache.object(forKey: key) {
            return cached as Data
        }

        // 2. Check disk cache
        let diskPath = diskFilePath(for: url)
        if let diskData = try? Data(contentsOf: diskPath) {
            dataCache.setObject(diskData as NSData, forKey: key, cost: diskData.count)
            return diskData
        }

        // 3. Fetch from network
        var request = URLRequest(url: url)
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await session.data(for: request)

        // Store in both caches
        dataCache.setObject(data as NSData, forKey: key, cost: data.count)
        try? data.write(to: diskPath)

        return data
    }

    // MARK: - Public: Decoded Image

    /// Fetches and decodes an image with caching:
    /// decoded image cache → raw data cache → disk → network.
    func image(for url: URL) async throws -> Image {
        let key = url.absoluteString as NSString

        // 1. Check decoded image cache
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        // 2. Get raw data (may hit data cache, disk cache, or network)
        let data = try await self.data(for: url)

        guard let image = Image(data: data) else {
            throw FileCacheError.decodingFailed
        }

        // 3. Store decoded image in memory cache
        imageCache.setObject(image, forKey: key, cost: data.count)

        return image
    }

    // MARK: - Private: Disk Cache

    private func diskFilePath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(filename)
    }

    // MARK: - Error

    enum FileCacheError: Error {
        case decodingFailed
    }
}
