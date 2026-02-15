//
//  FileCache.swift
//  MyLifeDB
//
//  General-purpose two-tier file cache:
//  1. In-memory NSCache for raw Data (fast, auto-evicts under pressure)
//  2. URLSession with configured URLCache for HTTP caching (honors Cache-Control, ETag, 304s)
//
//  Also provides a decoded image convenience cache on top.
//

import Foundation
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

    // MARK: - URLSession with HTTP cache

    private let session: URLSession

    // MARK: - Init

    private init() {
        // Disk cache: 200MB, Memory cache: 20MB
        let urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )

        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .useProtocolCachePolicy

        self.session = URLSession(configuration: config)

        // Raw data cache: 100 items, 80MB
        dataCache.countLimit = 100
        dataCache.totalCostLimit = 80 * 1024 * 1024

        // Decoded image cache: 150 items, 60MB
        imageCache.countLimit = 150
        imageCache.totalCostLimit = 60 * 1024 * 1024
    }

    // MARK: - Public: Raw Data

    /// Fetches file data with two-tier caching (in-memory + HTTP disk cache).
    func data(for url: URL) async throws -> Data {
        let key = url.absoluteString as NSString

        // 1. Check in-memory data cache
        if let cached = dataCache.object(forKey: key) {
            return cached as Data
        }

        // 2. Fetch via URLSession (URLCache handles HTTP caching / 304s)
        var request = URLRequest(url: url)
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await session.data(for: request)

        // 3. Store in memory cache
        dataCache.setObject(data as NSData, forKey: key, cost: data.count)

        return data
    }

    // MARK: - Public: Decoded Image

    /// Fetches and decodes an image with three-tier caching:
    /// decoded image cache → raw data cache → HTTP disk cache.
    func image(for url: URL) async throws -> Image {
        let key = url.absoluteString as NSString

        // 1. Check decoded image cache
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        // 2. Get raw data (may hit data cache or network)
        let data = try await self.data(for: url)

        guard let image = Image(data: data) else {
            throw FileCacheError.decodingFailed
        }

        // 3. Store decoded image in memory cache
        imageCache.setObject(image, forKey: key, cost: data.count)

        return image
    }

    // MARK: - Error

    enum FileCacheError: Error {
        case decodingFailed
    }
}
