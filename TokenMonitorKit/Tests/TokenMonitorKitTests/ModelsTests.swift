import Testing
import Foundation
@testable import TokenMonitorKit

@Suite struct ModelsTests {
    @Test func sourceStatusStaleDetection() {
        let old = Date(timeIntervalSinceNow: -600)
        let status = SourceStatus.fresh(fetchedAt: old)
        #expect(status.isStale(maxAge: 300, now: Date()))
        #expect(!status.isStale(maxAge: 3600, now: Date()))
    }

    @Test func dashboardStateEmpty() {
        let state = DashboardState.empty
        #expect(state.usage == nil)
        #expect(state.cost == nil)
        #expect(state.usageStatus == .unavailable(reason: "not loaded"))
    }
}
