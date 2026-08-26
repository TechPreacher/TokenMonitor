import Foundation

/// Wire format of the undocumented OAuth usage endpoint. Every field beyond
/// five_hour/seven_day is optional — the endpoint is unofficial and can change.
public struct OAuthUsageResponse: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let utilization: Double
        public let resetsAt: Date?
        enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }
    }
    public struct Limit: Decodable, Sendable {
        public struct Scope: Decodable, Sendable {
            public struct Model: Decodable, Sendable {
                public let displayName: String?
                enum CodingKeys: String, CodingKey { case displayName = "display_name" }
            }
            public let model: Model?
        }
        public let kind: String
        public let percent: Double
        public let resetsAt: Date?
        public let scope: Scope?
        public let isActive: Bool?
        enum CodingKeys: String, CodingKey {
            case kind, percent, scope, resetsAt = "resets_at", isActive = "is_active"
        }
    }
    public struct Money: Decodable, Sendable {
        public let amountMinor: Int
        public let exponent: Int
        enum CodingKeys: String, CodingKey { case amountMinor = "amount_minor", exponent }
        public var usd: Double { Double(amountMinor) / pow(10, Double(exponent)) }
    }
    public struct Spend: Decodable, Sendable {
        public let used: Money?
        public let limit: Money?
    }

    public let fiveHour: Window
    public let sevenDay: Window
    public let limits: [Limit]?
    public let spend: Spend?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour", sevenDay = "seven_day", limits, spend
    }

    /// The endpoint emits fractional-second ISO8601 timestamps.
    public static func decode(from data: Data) throws -> OAuthUsageResponse {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath,
                debugDescription: "Unparseable date: \(s)"))
        }
        return try decoder.decode(OAuthUsageResponse.self, from: data)
    }

    public func snapshot(fetchedAt: Date) -> UsageSnapshot {
        let mapped: [RateLimitInfo] = (limits ?? []).map { l in
            RateLimitInfo(
                kind: RateLimitInfo.Kind(rawValue: l.kind) ?? .other,
                percent: l.percent,
                resetsAt: l.resetsAt,
                scopeLabel: l.scope?.model?.displayName,
                isActive: l.isActive ?? false)
        }
        return UsageSnapshot(
            sessionPercent: fiveHour.utilization,
            sessionResetsAt: fiveHour.resetsAt,
            weeklyPercent: sevenDay.utilization,
            weeklyResetsAt: sevenDay.resetsAt,
            limits: mapped,
            extraUsageSpentUSD: spend?.used?.usd,
            extraUsageLimitUSD: spend?.limit?.usd,
            fetchedAt: fetchedAt)
    }
}
