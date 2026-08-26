import Testing
@testable import TokenMonitorKit

@Suite struct RefreshPolicyTests {
    @Test func exponentialBackoffWithCap() {
        let policy = RefreshPolicy(baseInterval: 60, maxInterval: 600)
        #expect(policy.nextDelay(consecutiveFailures: 0) == 60)
        #expect(policy.nextDelay(consecutiveFailures: 1) == 120)
        #expect(policy.nextDelay(consecutiveFailures: 2) == 240)
        #expect(policy.nextDelay(consecutiveFailures: 10) == 600)
    }
}
