import Testing
import Foundation
@testable import TokenMonitorKit

private let fixture = #"""
{"five_hour":{"utilization":12.0,"resets_at":"2026-08-26T16:39:59.765503+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"seven_day":{"utilization":19.0,"resets_at":"2026-08-27T16:59:59.765540+00:00","limit_dollars":null,"used_dollars":null,"remaining_dollars":null},"seven_day_opus":null,"nimbus_quill":{"utilization":0.0,"resets_at":null},"limits":[{"kind":"session","group":"session","percent":12,"severity":"normal","resets_at":"2026-08-26T16:39:59.765503+00:00","scope":null,"is_active":false},{"kind":"weekly_all","group":"weekly","percent":19,"severity":"normal","resets_at":"2026-08-27T16:59:59.765540+00:00","scope":null,"is_active":false},{"kind":"weekly_scoped","group":"weekly","percent":33,"severity":"normal","resets_at":"2026-08-27T16:59:59.765765+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}],"extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":0.0,"currency":"USD","decimal_places":2},"spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":{"amount_minor":5000,"currency":"USD","exponent":2},"percent":0,"severity":"normal","enabled":true}}
"""#

@Suite struct OAuthUsageResponseTests {
    @Test func decodesRealResponse() throws {
        let response = try OAuthUsageResponse.decode(from: Data(fixture.utf8))
        let snap = response.snapshot(fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(snap.sessionPercent == 12.0)
        #expect(snap.weeklyPercent == 19.0)
        #expect(snap.sessionResetsAt != nil)
        #expect(snap.limits.count == 3)
        let scoped = try #require(snap.limits.first { $0.kind == .weeklyScoped })
        #expect(scoped.percent == 33)
        #expect(scoped.scopeLabel == "Fable")
        #expect(scoped.isActive)
        // spend: 0 of 5000 minor units, exponent 2 -> 0.00 of 50.00 USD
        #expect(snap.extraUsageSpentUSD == 0.0)
        #expect(snap.extraUsageLimitUSD == 50.0)
    }

    @Test func toleratesMissingOptionalSections() throws {
        let minimal = #"{"five_hour":{"utilization":5.0,"resets_at":null},"seven_day":{"utilization":7.5,"resets_at":null}}"#
        let snap = try OAuthUsageResponse.decode(from: Data(minimal.utf8))
            .snapshot(fetchedAt: .now)
        #expect(snap.sessionPercent == 5.0)
        #expect(snap.weeklyPercent == 7.5)
        #expect(snap.limits.isEmpty)
        #expect(snap.extraUsageSpentUSD == nil)
    }

    @Test func unknownLimitKindMapsToOther() throws {
        let json = #"{"five_hour":{"utilization":1,"resets_at":null},"seven_day":{"utilization":2,"resets_at":null},"limits":[{"kind":"brand_new_kind","percent":50,"resets_at":null,"scope":null,"is_active":false}]}"#
        let snap = try OAuthUsageResponse.decode(from: Data(json.utf8)).snapshot(fetchedAt: .now)
        #expect(snap.limits.first?.kind == .other)
    }
}
