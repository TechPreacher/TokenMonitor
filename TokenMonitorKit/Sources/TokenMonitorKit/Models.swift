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

/// One live Claude Code session and how full its context window is.
public struct ActiveSession: Sendable, Equatable, Identifiable {
    public let sessionId: String
    /// Project name shown in the UI (cwd basename, fallback transcript folder name).
    public let label: String
    public let contextTokens: Int
    public let windowTokens: Int
    /// 0...100
    public let percent: Double
    public let lastActivity: Date

    public var id: String { sessionId }

    public init(sessionId: String, label: String, contextTokens: Int,
                windowTokens: Int, percent: Double, lastActivity: Date) {
        self.sessionId = sessionId
        self.label = label
        self.contextTokens = contextTokens
        self.windowTokens = windowTokens
        self.percent = percent
        self.lastActivity = lastActivity
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
    /// Claude Code sessions with recent transcript activity; empty when none or unreadable.
    public var activeSessions: [ActiveSession]

    public init(usage: UsageSnapshot?, usageStatus: SourceStatus,
                transcripts: TranscriptTotals?, transcriptsStatus: SourceStatus,
                cost: CostSnapshot?, costStatus: SourceStatus,
                activeSessions: [ActiveSession] = []) {
        self.usage = usage
        self.usageStatus = usageStatus
        self.transcripts = transcripts
        self.transcriptsStatus = transcriptsStatus
        self.cost = cost
        self.costStatus = costStatus
        self.activeSessions = activeSessions
    }

    public static let empty = DashboardState(
        usage: nil, usageStatus: .unavailable(reason: "not loaded"),
        transcripts: nil, transcriptsStatus: .unavailable(reason: "not loaded"),
        cost: nil, costStatus: .unavailable(reason: "not loaded"))
}
