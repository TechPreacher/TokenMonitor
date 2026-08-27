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
    private let sessionsReader: ActiveSessionsReader?
    private let modelCatalog: (any ModelCatalogProviding)?
    /// Context windows fetched from the Models API; empty until first success.
    private var modelWindows: [String: Int] = [:]
    private let networkPolicy = RefreshPolicy(baseInterval: 60)
    private let localPolicy = RefreshPolicy(baseInterval: 30, maxInterval: 120)
    private var networkFailures = 0
    private var localFailures = 0
    private var pollTasks: [Task<Void, Never>] = []

    init(usageProvider: any UsageProviding,
         costProvider: any CostProviding,
         transcriptReader: TranscriptUsageReader?,
         sessionsReader: ActiveSessionsReader? = nil,
         modelCatalog: (any ModelCatalogProviding)? = nil) {
        self.usageProvider = usageProvider
        self.costProvider = costProvider
        self.transcriptReader = transcriptReader
        self.sessionsReader = sessionsReader
        self.modelCatalog = modelCatalog
    }

    static func live() -> DashboardViewModel {
        let store = KeychainCredentialStore()
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        return DashboardViewModel(
            usageProvider: ClaudeOAuthClient(credentials: store),
            costProvider: AdminCostClient(credentials: store),
            transcriptReader: TranscriptUsageReader(rootDirectory: root),
            sessionsReader: ActiveSessionsReader(rootDirectory: root),
            modelCatalog: ModelCatalogClient(credentials: store))
    }

    func refreshNetworkSources() async {
        // Model windows change only at model launches: fetch once, retry each
        // tick until it succeeds, static mapping covers the meantime.
        if modelWindows.isEmpty, let modelCatalog {
            modelWindows = (try? await modelCatalog.fetchContextWindows()) ?? [:]
        }
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
        let now = Date()
        var totals: Result<TranscriptTotals, Error>?
        if let transcriptReader {
            do {
                totals = .success(try transcriptReader.totals(now: now, calendar: .current))
                localFailures = 0
            } catch {
                totals = .failure(error)
                localFailures += 1
            }
        }
        let sessions: Result<[ActiveSession], Error>? = sessionsReader.map { [modelWindows] reader in
            Result { try reader.sessions(now: now, catalog: modelWindows) }
        }
        state = UsageAggregator.merge(previous: state, usage: nil, transcripts: totals,
                                      cost: nil, sessions: sessions)
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
