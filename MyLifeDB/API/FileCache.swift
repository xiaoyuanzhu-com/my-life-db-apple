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
//  Supports metadata-aware invalidation: callers can pass an expected
//  modifiedAt timestamp. If the cached entry is older, it is treated as
//  stale and re-fetched from the server.
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

    // MARK: - In-memory metadata cache (URL → modifiedAt epoch ms)

    private let modifiedAtCache = NSCache<NSString, NSNumber>()

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

        // Metadata cache: lightweight Int64 values, generous limit
        modifiedAtCache.countLimit = 500

        // Disk cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheDir = cacheDir.appendingPathComponent("FileCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Public: Raw Data

    /// Fetches file data with three-tier caching:
    /// in-memory → disk → network.
    ///
    /// When `expectedModifiedAt` is provided (epoch milliseconds), the cached
    /// entry is validated against it. If the cache is older, it is treated as
    /// stale and re-fetched from the server.
    func data(for url: URL, expectedModifiedAt: Int64? = nil) async throws -> Data {
        let key = url.absoluteString as NSString

        // 1. Check in-memory data cache
        if let cached = dataCache.object(forKey: key) {
            let cachedMod = modifiedAtCache.object(forKey: key)?.int64Value
            if isFresh(cachedModifiedAt: cachedMod, expectedModifiedAt: expectedModifiedAt) {
                return cached as Data
            }
            // Stale — evict from all memory caches
            dataCache.removeObject(forKey: key)
            imageCache.removeObject(forKey: key)
            modifiedAtCache.removeObject(forKey: key)
        }

        // 2. Check disk cache
        let diskPath = diskFilePath(for: url)
        let metaPath = diskMetaPath(for: url)
        if let diskData = try? Data(contentsOf: diskPath) {
            let diskMod = loadDiskModifiedAt(from: metaPath)
            if isFresh(cachedModifiedAt: diskMod, expectedModifiedAt: expectedModifiedAt) {
                // Fresh — promote to memory cache
                dataCache.setObject(diskData as NSData, forKey: key, cost: diskData.count)
                if let mod = diskMod {
                    modifiedAtCache.setObject(NSNumber(value: mod), forKey: key)
                }
                return diskData
            }
            // Stale on disk — clean up stale files
            try? FileManager.default.removeItem(at: diskPath)
            try? FileManager.default.removeItem(at: metaPath)
        }

        // 3. Fetch from network
        var request = URLRequest(url: url)
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        // Determine modifiedAt: prefer server's Last-Modified header,
        // fall back to the caller's expected value
        let modifiedAt = parseLastModified(from: response) ?? expectedModifiedAt

        // Store in memory caches
        dataCache.setObject(data as NSData, forKey: key, cost: data.count)
        if let mod = modifiedAt {
            modifiedAtCache.setObject(NSNumber(value: mod), forKey: key)
        }

        // Store on disk with metadata sidecar
        try? data.write(to: diskPath)
        if let mod = modifiedAt {
            saveDiskModifiedAt(mod, to: metaPath)
        }

        return data
    }

    // MARK: - Public: Decoded Image

    /// Fetches and decodes an image with caching:
    /// decoded image cache → raw data cache → disk → network.
    ///
    /// When `expectedModifiedAt` is provided, stale cached entries are
    /// invalidated and re-fetched.
    func image(for url: URL, expectedModifiedAt: Int64? = nil) async throws -> Image {
        let key = url.absoluteString as NSString

        // 1. Check decoded image cache
        if let cached = imageCache.object(forKey: key) {
            let cachedMod = modifiedAtCache.object(forKey: key)?.int64Value
            if isFresh(cachedModifiedAt: cachedMod, expectedModifiedAt: expectedModifiedAt) {
                return cached
            }
            // Stale — evict decoded image
            imageCache.removeObject(forKey: key)
        }

        // 2. Get raw data (may hit data cache, disk cache, or network)
        let data = try await self.data(for: url, expectedModifiedAt: expectedModifiedAt)

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

    // MARK: - Public: Invalidation

    /// Explicitly invalidate all cached data for a URL.
    func invalidate(for url: URL) {
        let key = url.absoluteString as NSString
        dataCache.removeObject(forKey: key)
        imageCache.removeObject(forKey: key)
        modifiedAtCache.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: diskFilePath(for: url))
        try? FileManager.default.removeItem(at: diskMetaPath(for: url))
    }

    // MARK: - Freshness Check

    /// Returns true if the cached entry is still fresh.
    /// - No expected timestamp → always fresh (backward-compatible)
    /// - Expected timestamp but no cached metadata → stale (conservative)
    /// - Cached modifiedAt ≥ expected → fresh
    private func isFresh(cachedModifiedAt: Int64?, expectedModifiedAt: Int64?) -> Bool {
        guard let expected = expectedModifiedAt else { return true }
        guard let cached = cachedModifiedAt else { return false }
        return cached >= expected
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

    // MARK: - Private: Last-Modified Parsing

    private func parseLastModified(from response: URLResponse) -> Int64? {
        guard let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Last-Modified") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        guard let date = formatter.date(from: header) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    // MARK: - Private: Disk Cache Paths

    private func diskFilePath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(filename)
    }

    private func diskMetaPath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheDir.appendingPathComponent(filename + ".meta")
    }

    // MARK: - Private: Disk Metadata

    private struct DiskMeta: Codable {
        let modifiedAt: Int64
    }

    private func loadDiskModifiedAt(from path: URL) -> Int64? {
        guard let data = try? Data(contentsOf: path),
              let meta = try? JSONDecoder().decode(DiskMeta.self, from: data) else { return nil }
        return meta.modifiedAt
    }

    private func saveDiskModifiedAt(_ modifiedAt: Int64, to path: URL) {
        guard let data = try? JSONEncoder().encode(DiskMeta(modifiedAt: modifiedAt)) else { return }
        try? data.write(to: path)
    }

    // MARK: - Error

    enum FileCacheError: Error {
        case decodingFailed
    }
}
