import Foundation

/// Pure merge of per-source fetch results into the next DashboardState.
public enum UsageAggregator {
    public static func merge(previous: DashboardState,
                             usage: Result<UsageSnapshot, Error>?,
                             transcripts: Result<TranscriptTotals, Error>?,
                             cost: Result<CostSnapshot, Error>?,
                             sessions: Result<[ActiveSession], Error>? = nil) -> DashboardState {
        var next = previous

        // Sessions degrade silently: failures keep the previous list, no badge.
        if case .success(let list) = sessions { next.activeSessions = list }

        switch usage {
        case .success(let snap):
            next.usage = snap
            next.usageStatus = .fresh(fetchedAt: snap.fetchedAt)
        case .failure(let error):
            if next.usage == nil { next.usageStatus = .unavailable(reason: "\(error)") }
        case nil: break
        }

        switch transcripts {
        case .success(let totals):
            next.transcripts = totals
            next.transcriptsStatus = .fresh(fetchedAt: totals.fetchedAt)
        case .failure(let error):
            if next.transcripts == nil { next.transcriptsStatus = .unavailable(reason: "\(error)") }
        case nil: break
        }

        switch cost {
        case .success(let snap):
            next.cost = snap
            next.costStatus = .fresh(fetchedAt: snap.fetchedAt)
        case .failure(let error):
            if next.cost == nil { next.costStatus = .unavailable(reason: "\(error)") }
        case nil: break
        }

        return next
    }
}
