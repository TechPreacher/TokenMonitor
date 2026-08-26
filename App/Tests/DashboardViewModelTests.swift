// App/Tests/DashboardViewModelTests.swift
import Testing
import Foundation
import TokenMonitorKit
@testable import TokenMonitor

struct StubUsage: UsageProviding {
    var result: Result<UsageSnapshot, Error>
    func fetchUsage() async throws -> UsageSnapshot { try result.get() }
}
struct StubCost: CostProviding {
    var result: Result<CostSnapshot, Error>
    func fetchMonthToDateCost(now: Date) async throws -> CostSnapshot { try result.get() }
}

@MainActor
@Suite struct DashboardViewModelTests {
    @Test func refreshMergesSuccessesIntoState() async {
        let usage = UsageSnapshot(sessionPercent: 55, sessionResetsAt: nil, weeklyPercent: 5,
                                  weeklyResetsAt: nil, limits: [], extraUsageSpentUSD: nil,
                                  extraUsageLimitUSD: nil, fetchedAt: .now)
        let cost = CostSnapshot(monthToDateUSD: 12.34, fetchedAt: .now)
        let vm = DashboardViewModel(usageProvider: StubUsage(result: .success(usage)),
                                    costProvider: StubCost(result: .success(cost)),
                                    transcriptReader: nil)
        await vm.refreshNetworkSources()
        #expect(vm.state.usage?.sessionPercent == 55)
        #expect(vm.state.cost?.monthToDateUSD == 12.34)
    }

    @Test func failingSourceDoesNotBlockOthers() async {
        let cost = CostSnapshot(monthToDateUSD: 1.0, fetchedAt: .now)
        let vm = DashboardViewModel(
            usageProvider: StubUsage(result: .failure(FetchError.httpStatus(500))),
            costProvider: StubCost(result: .success(cost)),
            transcriptReader: nil)
        await vm.refreshNetworkSources()
        #expect(vm.state.cost?.monthToDateUSD == 1.0)
        if case .unavailable = vm.state.usageStatus {} else {
            Issue.record("usage should be unavailable")
        }
    }
}
