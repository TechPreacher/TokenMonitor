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

    @Test func localRefreshPopulatesActiveSessions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("-Users-me-Code-ProjectX")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // swiftlint:disable:next line_length
        let line = #"{"type":"assistant","timestamp":"2026-08-27T07:00:00.000Z","cwd":"/Users/me/Code/ProjectX","sessionId":"abc","message":{"model":"claude-fable-5","usage":{"input_tokens":2,"output_tokens":700,"cache_creation_input_tokens":5000,"cache_read_input_tokens":45000}}}"#
        try line.write(to: dir.appendingPathComponent("abc.jsonl"),
                       atomically: true, encoding: .utf8)

        let vm = DashboardViewModel(
            usageProvider: StubUsage(result: .failure(FetchError.httpStatus(500))),
            costProvider: StubCost(result: .failure(FetchError.httpStatus(500))),
            transcriptReader: nil,
            sessionsReader: ActiveSessionsReader(rootDirectory: root))
        await vm.refreshLocalSources()
        #expect(vm.state.activeSessions.map(\.label) == ["ProjectX"])
        #expect(vm.state.activeSessions.first?.contextTokens == 50002)
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
