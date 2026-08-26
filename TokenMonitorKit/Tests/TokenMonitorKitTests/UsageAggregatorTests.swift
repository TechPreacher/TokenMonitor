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
        let t = Date()
        let state = UsageAggregator.merge(previous: .empty,
                                          usage: .success(sampleUsage(at: t)),
                                          transcripts: nil, cost: nil)
        #expect(state.usage?.sessionPercent == 10)
        #expect(state.usageStatus == .fresh(fetchedAt: t))
        // untouched sources unchanged
        #expect(state.costStatus == .unavailable(reason: "not loaded"))
    }

    @Test func failureKeepsPreviousValue() {
        let t = Date(timeIntervalSinceNow: -120)
        var previous = DashboardState.empty
        previous.usage = sampleUsage(at: t)
        previous.usageStatus = .fresh(fetchedAt: t)
        let state = UsageAggregator.merge(previous: previous,
                                          usage: .failure(FetchError.httpStatus(500)),
                                          transcripts: nil, cost: nil)
        #expect(state.usage?.sessionPercent == 10)          // value retained
        #expect(state.usageStatus == .fresh(fetchedAt: t))  // stale-by-age, not wiped
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
