import Foundation

/// One rate-limit gauge (session window, weekly, model-scoped weekly, ...).
public struct RateLimitInfo: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case session, weeklyAll = "weekly_all", weeklyScoped = "weekly_scoped", other
    }
    public let kind: Kind
    /// 0...100
    public let percent: Double
    public let resetsAt: Date?
    /// e.g. "Fable" for model-scoped limits; nil otherwise.
    public let scopeLabel: String?
    public let isActive: Bool

    public init(kind: Kind, percent: Double, resetsAt: Date?, scopeLabel: String?, isActive: Bool) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.scopeLabel = scopeLabel
        self.isActive = isActive
    }
}

/// Subscription usage as reported by the OAuth usage endpoint (or estimated from JSONL).
public struct UsageSnapshot: Sendable, Equatable {
    /// 0...100
    public let sessionPercent: Double
    public let sessionResetsAt: Date?
    /// 0...100
    public let weeklyPercent: Double
    public let weeklyResetsAt: Date?
    public let limits: [RateLimitInfo]
    /// Extra-usage credits spent, in USD. nil when unknown.
    public let extraUsageSpentUSD: Double?
    /// Extra-usage credit cap, in USD. nil when unknown.
    public let extraUsageLimitUSD: Double?
    public let fetchedAt: Date

    public init(sessionPercent: Double, sessionResetsAt: Date?, weeklyPercent: Double,
                weeklyResetsAt: Date?, limits: [RateLimitInfo],
                extraUsageSpentUSD: Double?, extraUsageLimitUSD: Double?, fetchedAt: Date) {
        self.sessionPercent = sessionPercent
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.limits = limits
        self.extraUsageSpentUSD = extraUsageSpentUSD
        self.extraUsageLimitUSD = extraUsageLimitUSD
        self.fetchedAt = fetchedAt
    }
}

/// Token totals derived from local JSONL transcripts.
public struct TranscriptTotals: Sendable, Equatable {
    public let tokensToday: Int
    public let tokensThisSessionWindow: Int
    public let fetchedAt: Date

    public init(tokensToday: Int, tokensThisSessionWindow: Int, fetchedAt: Date) {
        self.tokensToday = tokensToday
        self.tokensThisSessionWindow = tokensThisSessionWindow
        self.fetchedAt = fetchedAt
    }
}

/// API spend from the Admin cost report.
public struct CostSnapshot: Sendable, Equatable {
    public let monthToDateUSD: Double
    public let fetchedAt: Date

    public init(monthToDateUSD: Double, fetchedAt: Date) {
        self.monthToDateUSD = monthToDateUSD
        self.fetchedAt = fetchedAt
    }
}

public enum SourceStatus: Sendable, Equatable {
    case fresh(fetchedAt: Date)
    case unavailable(reason: String)

    public func isStale(maxAge: TimeInterval, now: Date) -> Bool {
        if case .fresh(let fetchedAt) = self {
            return now.timeIntervalSince(fetchedAt) > maxAge
        }
        return false
    }
}

/// Everything the UI renders.
public struct DashboardState: Sendable, Equatable {
    public var usage: UsageSnapshot?
    public var usageStatus: SourceStatus
    public var transcripts: TranscriptTotals?
    public var transcriptsStatus: SourceStatus
    public var cost: CostSnapshot?
    public var costStatus: SourceStatus

    public init(usage: UsageSnapshot?, usageStatus: SourceStatus,
                transcripts: TranscriptTotals?, transcriptsStatus: SourceStatus,
                cost: CostSnapshot?, costStatus: SourceStatus) {
        self.usage = usage
        self.usageStatus = usageStatus
        self.transcripts = transcripts
        self.transcriptsStatus = transcriptsStatus
        self.cost = cost
        self.costStatus = costStatus
    }

    public static let empty = DashboardState(
        usage: nil, usageStatus: .unavailable(reason: "not loaded"),
        transcripts: nil, transcriptsStatus: .unavailable(reason: "not loaded"),
        cost: nil, costStatus: .unavailable(reason: "not loaded"))
}
