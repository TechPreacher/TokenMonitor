import Testing
import Foundation
@testable import TokenMonitorKit

@Suite struct UsageAggregatorTests {
    func sampleUsage(at date: Date) -> UsageSnapshot {
        UsageSnapshot(sessionPercent: 10, sessionResetsAt: nil, weeklyPercent: 20,
                      weeklyResetsAt: nil, limits: [], extraUsageSpentUSD: nil,
                      extraUsageLimitUSD: nil, fetchedAt: date)
    }

    @Test func successReplacesValueAndFreshens() {
        let now = Date()
        let state = UsageAggregator.merge(previous: .empty,
                                          usage: .success(sampleUsage(at: now)),
                                          transcripts: nil, cost: nil)
        #expect(state.usage?.sessionPercent == 10)
        #expect(state.usageStatus == .fresh(fetchedAt: now))
        // untouched sources unchanged
        #expect(state.costStatus == .unavailable(reason: "not loaded"))
    }

    @Test func failureKeepsPreviousValue() {
        let past = Date(timeIntervalSinceNow: -120)
        var previous = DashboardState.empty
        previous.usage = sampleUsage(at: past)
        previous.usageStatus = .fresh(fetchedAt: past)
        let state = UsageAggregator.merge(previous: previous,
                                          usage: .failure(FetchError.httpStatus(500)),
                                          transcripts: nil, cost: nil)
        #expect(state.usage?.sessionPercent == 10)          // value retained
        #expect(state.usageStatus == .fresh(fetchedAt: past))  // stale-by-age, not wiped
    }

    @Test func failureWithNoPreviousBecomesUnavailable() {
        let state = UsageAggregator.merge(previous: .empty,
                                          usage: nil, transcripts: nil,
                                          cost: .failure(FetchError.credentialsUnavailable))
        #expect(state.cost == nil)
        if case .unavailable = state.costStatus {} else {
            Issue.record("expected unavailable, got \(state.costStatus)")
        }
    }
}

@Suite struct ActiveSessionsMergeTests {
    func session(_ id: String) -> ActiveSession {
        ActiveSession(sessionId: id, label: "Proj", contextTokens: 100_000,
                      windowTokens: 200_000, percent: 50, lastActivity: Date())
    }

    @Test func successReplacesSessions() {
        let state = UsageAggregator.merge(previous: .empty, usage: nil, transcripts: nil,
                                          cost: nil, sessions: .success([session("a")]))
        #expect(state.activeSessions.map(\.sessionId) == ["a"])
    }

    @Test func failureKeepsPreviousSessions() {
        var previous = DashboardState.empty
        previous.activeSessions = [session("a")]
        let state = UsageAggregator.merge(previous: previous, usage: nil, transcripts: nil,
                                          cost: nil, sessions: .failure(FetchError.httpStatus(500)))
        #expect(state.activeSessions.map(\.sessionId) == ["a"])
    }

    @Test func nilLeavesSessionsUntouched() {
        var previous = DashboardState.empty
        previous.activeSessions = [session("a")]
        let state = UsageAggregator.merge(previous: previous, usage: nil,
                                          transcripts: nil, cost: nil)
        #expect(state.activeSessions.map(\.sessionId) == ["a"])
    }
}
