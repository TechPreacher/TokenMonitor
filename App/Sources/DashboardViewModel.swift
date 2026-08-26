// App/Sources/DashboardViewModel.swift
import Foundation
import Observation
import TokenMonitorKit

@MainActor
@Observable
final class DashboardViewModel {
    var state: DashboardState = .empty
    var isPinned = false

    private let usageProvider: any UsageProviding
    private let costProvider: any CostProviding
    private let transcriptReader: TranscriptUsageReader?
    private let networkPolicy = RefreshPolicy(baseInterval: 60)
    private let localPolicy = RefreshPolicy(baseInterval: 30, maxInterval: 120)
    private var networkFailures = 0
    private var localFailures = 0
    private var pollTasks: [Task<Void, Never>] = []

    init(usageProvider: any UsageProviding,
         costProvider: any CostProviding,
         transcriptReader: TranscriptUsageReader?) {
        self.usageProvider = usageProvider
        self.costProvider = costProvider
        self.transcriptReader = transcriptReader
    }

    static func live() -> DashboardViewModel {
        let store = KeychainCredentialStore()
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        return DashboardViewModel(
            usageProvider: ClaudeOAuthClient(credentials: store),
            costProvider: AdminCostClient(credentials: store),
            transcriptReader: TranscriptUsageReader(rootDirectory: root))
    }

    func refreshNetworkSources() async {
        async let usageResult: Result<UsageSnapshot, Error> = {
            do { return .success(try await usageProvider.fetchUsage()) }
            catch { return .failure(error) }
        }()
        async let costResult: Result<CostSnapshot, Error> = {
            do { return .success(try await costProvider.fetchMonthToDateCost(now: Date())) }
            catch { return .failure(error) }
        }()
        let (usage, cost) = await (usageResult, costResult)
        if case .failure = usage { networkFailures += 1 } else { networkFailures = 0 }
        state = UsageAggregator.merge(previous: state, usage: usage, transcripts: nil, cost: cost)
    }

    func refreshLocalSources() async {
        guard let transcriptReader else { return }
        let result: Result<TranscriptTotals, Error>
        do {
            result = .success(try transcriptReader.totals(now: Date(), calendar: .current))
            localFailures = 0
        } catch {
            result = .failure(error)
            localFailures += 1
        }
        state = UsageAggregator.merge(previous: state, usage: nil, transcripts: result, cost: nil)
    }

    func startPolling() {
        stopPolling()
        pollTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNetworkSources()
                let delay = self.networkPolicy.nextDelay(consecutiveFailures: self.networkFailures)
                try? await Task.sleep(for: .seconds(delay))
            }
        })
        pollTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshLocalSources()
                let delay = self.localPolicy.nextDelay(consecutiveFailures: self.localFailures)
                try? await Task.sleep(for: .seconds(delay))
            }
        })
    }

    func stopPolling() {
        pollTasks.forEach { $0.cancel() }
        pollTasks.removeAll()
    }
}
