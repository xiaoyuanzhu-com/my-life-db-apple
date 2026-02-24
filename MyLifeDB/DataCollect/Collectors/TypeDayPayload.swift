//
//  TypeDayPayload.swift
//  MyLifeDB
//
//  Deterministic per-type-per-day JSON payload for health data sync.
//  One file per (type, date) pair — no device info, no syncedAt timestamp.
//  Encoding is fully deterministic: sorted keys, sorted samples.
//

import Foundation

struct TypeDayPayload: Encodable {
    let type: String
    let date: String
    let timezone: String
    let unit: String?
    let samples: [RawHealthSample]

    enum CodingKeys: String, CodingKey {
        case type, date, timezone, unit, samples
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(date, forKey: .date)
        try container.encode(timezone, forKey: .timezone)
        try container.encodeIfPresent(unit, forKey: .unit)

        let sorted = samples.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
            return a.source < b.source
        }
        try container.encode(sorted, forKey: .samples)
    }

    static func encode(_ payload: TypeDayPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(payload)
    }
}
