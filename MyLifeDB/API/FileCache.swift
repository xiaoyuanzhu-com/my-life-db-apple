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

        // Raw data cache: 80 items, 50MB
        // Stores compressed file bytes. Images are evicted from here once
        // decoded into imageCache, so this mainly holds non-image files and
        // images that haven't been decoded yet.
        dataCache.countLimit = 80
        dataCache.totalCostLimit = 50 * 1024 * 1024

        // Decoded image cache: 30 items, 120MB
        // Cost is the actual decoded bitmap size (width × height × 4 bytes),
        // NOT the compressed file size. 120MB ≈ 2–3 full-resolution photos.
        imageCache.countLimit = 30
        imageCache.totalCostLimit = 120 * 1024 * 1024

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

        // 3. Store decoded image using actual bitmap cost, not compressed size.
        // A decoded image occupies width × height × bytesPerPixel in memory,
        // which can be 10–50× larger than the compressed JPEG/PNG data.
        let bitmapCost = Self.decodedByteCount(of: image, compressedSize: data.count)
        imageCache.setObject(image, forKey: key, cost: bitmapCost)

        // 4. Evict the compressed data from dataCache — no need to keep both
        // the raw bytes and the decoded bitmap in memory simultaneously.
        // The raw data is still on disk and will be re-read if needed.
        dataCache.removeObject(forKey: key)

        return image
    }

    // MARK: - Bitmap Cost Estimation

    /// Returns the estimated in-memory byte count of a decoded image.
    /// Falls back to 4× compressed size if pixel dimensions aren't available.
    private static func decodedByteCount(of image: Image, compressedSize: Int) -> Int {
        #if os(iOS) || os(visionOS)
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        #elseif os(macOS)
        guard let rep = image.representations.first else {
            return max(compressedSize * 4, 1)
        }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        #endif
        let bytesPerPixel = 4 // RGBA
        let estimated = w * h * bytesPerPixel
        // Guard against zero (e.g. vector/PDF images with no pixel backing)
        return estimated > 0 ? estimated : max(compressedSize * 4, 1)
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
