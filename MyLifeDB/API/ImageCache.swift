//
//  ImageCache.swift
//  MyLifeDB
//
//  Two-tier image cache:
//  1. In-memory NSCache for decoded platform images (fast, auto-evicts under pressure)
//  2. URLSession with configured URLCache for HTTP caching (honors Cache-Control, ETag, 304s)
//

import Foundation
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class ImageCache: @unchecked Sendable {

    #if os(iOS) || os(visionOS)
    typealias Image = UIImage
    #elseif os(macOS)
    typealias Image = NSImage
    #endif

    static let shared = ImageCache()

    // MARK: - In-memory cache for decoded images

    private let memoryCache = NSCache<NSString, Image>()

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

        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 60 * 1024 * 1024 // 60MB decoded images
    }

    // MARK: - Public

    func image(for url: URL) async throws -> Image {
        let key = url.absoluteString as NSString

        // 1. Check in-memory decoded image cache
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Fetch via URLSession (URLCache handles HTTP caching / 304s)
        var request = URLRequest(url: url)
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await session.data(for: request)

        guard let image = Image(data: data) else {
            throw ImageCacheError.decodingFailed
        }

        // 3. Store decoded image in memory cache
        memoryCache.setObject(image, forKey: key, cost: data.count)

        return image
    }

    // MARK: - Error

    enum ImageCacheError: Error {
        case decodingFailed
    }
}
