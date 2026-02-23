//
//  WorkoutFile.swift
//  MyLifeDB
//
//  JSON schema for workout-<UUID>.json files.
//  One file per workout event, with embedded GPS route.
//

import Foundation

/// A raw GPS point from HKWorkoutRoute / CLLocation.
/// All fields stored as-is — no downsampling.
struct RoutePoint: Encodable {
    let timestamp: Date
    let lat: Double
    let lon: Double
    let alt: Double
    let hAcc: Double   // horizontal accuracy, metres
    let vAcc: Double   // vertical accuracy, metres
    let speed: Double  // m/s, negative = invalid
    let speedAcc: Double
    let course: Double // degrees clockwise from north, negative = invalid
    let courseAcc: Double

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case lat, lon, alt
        case hAcc = "h_acc"
        case vAcc = "v_acc"
        case speed
        case speedAcc = "speed_acc"
        case course
        case courseAcc = "course_acc"
    }
}

/// A stat value with its unit (e.g. energy: 435 kcal).
struct StatValue: Encodable {
    let value: Double
    let unit: String
}

/// Top-level structure for a workout-<UUID>.json file.
struct WorkoutFile: Encodable {
    let uuid: String
    let activityType: String
    let start: Date
    let end: Date
    let durationS: Double
    let source: String
    let device: String?
    let syncedAt: Date
    let deviceInfo: DeviceInfo
    let stats: [String: StatValue]
    let metadata: [String: Any]?
    let route: [RoutePoint]?   // nil = no GPS (indoor workout)

    enum CodingKeys: String, CodingKey {
        case uuid
        case activityType = "activity_type"
        case start, end
        case durationS = "duration_s"
        case source, device
        case syncedAt = "synced_at"
        case deviceInfo = "device_info"
        case stats, metadata, route
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uuid,         forKey: .uuid)
        try c.encode(activityType, forKey: .activityType)
        try c.encode(start,        forKey: .start)
        try c.encode(end,          forKey: .end)
        try c.encode(durationS,    forKey: .durationS)
        try c.encode(source,       forKey: .source)
        try c.encodeIfPresent(device,     forKey: .device)
        try c.encode(syncedAt,     forKey: .syncedAt)
        try c.encode(deviceInfo,   forKey: .deviceInfo)
        try c.encode(stats,        forKey: .stats)
        try c.encodeIfPresent(route, forKey: .route)
        if let metadata, !metadata.isEmpty {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            try c.encode(AnyCodable(jsonObject), forKey: .metadata)
        }
    }
}
