import Testing
import Foundation
@testable import TokenMonitorKit

struct MockAdminCredentials: CredentialStore {
    var adminKey: String? = "sk-ant-admin01-test"
    func readClaudeCodeOAuthToken() throws -> String { throw CredentialError.notFound }
    func readAdminAPIKey() -> String? { adminKey }
    func writeAdminAPIKey(_ key: String) throws {}
}

@Suite(.serialized) struct AdminCostClientTests {
    @Test func sumsAmountsAcrossBuckets() async throws {
        // swiftlint:disable:next line_length
        let body = #"{"data":[{"starting_at":"2026-08-01T00:00:00Z","ending_at":"2026-08-02T00:00:00Z","results":[{"amount":"123.78912","currency":"USD"},{"amount":"100.0","currency":"USD"}]},{"starting_at":"2026-08-02T00:00:00Z","ending_at":"2026-08-03T00:00:00Z","results":[]}],"has_more":false,"next_page":null}"#
        StubURLProtocol.responses["/v1/organizations/cost_report"] = (200, Data(body.utf8))
        let client = AdminCostClient(credentials: MockAdminCredentials(), session: stubbedSession())
        let snap = try await client.fetchMonthToDateCost(now: Date())
        // (123.78912 + 100.0) cents = 2.2378912 USD
        #expect(abs(snap.monthToDateUSD - 2.2378912) < 0.0001)
        let req = try #require(StubURLProtocol.lastRequests["/v1/organizations/cost_report"])
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-admin01-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let query = req.url?.query ?? ""
        #expect(query.contains("starting_at="))
        #expect(query.contains("limit=31"))
    }

    @Test func noAdminKeyThrowsCredentialsUnavailable() async {
        let client = AdminCostClient(credentials: MockAdminCredentials(adminKey: nil),
                                     session: stubbedSession())
        await #expect(throws: FetchError.credentialsUnavailable) {
            _ = try await client.fetchMonthToDateCost(now: Date())
        }
    }

    @Test func http403Throws() async {
        StubURLProtocol.responses["/v1/organizations/cost_report"] = (403, Data())
        let client = AdminCostClient(credentials: MockAdminCredentials(), session: stubbedSession())
        await #expect(throws: FetchError.httpStatus(403)) {
            _ = try await client.fetchMonthToDateCost(now: Date())
        }
    }

    /// Finding 1: exercises the repeat/while pagination loop across two pages
    /// using StubURLProtocol's per-path response queue, and asserts the
    /// second HTTP request actually carried the `page` cursor from the first
    /// page's `next_page`.
    @Test func paginatesAcrossMultiplePages() async throws {
        let path = "/v1/organizations/cost_report"
        StubURLProtocol.requestHistory[path] = []
        StubURLProtocol.responseQueues[path] = []
        let page1 = #"{"data":[{"starting_at":"2026-08-01T00:00:00Z","ending_at":"2026-08-02T00:00:00Z","results":[{"amount":"100.0","currency":"USD"}]}],"has_more":true,"next_page":"page_2"}"#
        let page2 = #"{"data":[{"starting_at":"2026-08-02T00:00:00Z","ending_at":"2026-08-03T00:00:00Z","results":[{"amount":"50.0","currency":"USD"}]}],"has_more":false,"next_page":null}"#
        StubURLProtocol.responseQueues[path] = [
            (200, Data(page1.utf8)),
            (200, Data(page2.utf8)),
        ]
        let client = AdminCostClient(credentials: MockAdminCredentials(), session: stubbedSession())
        let snap = try await client.fetchMonthToDateCost(now: Date())
        // (100.0 + 50.0) cents = 1.50 USD
        #expect(abs(snap.monthToDateUSD - 1.50) < 0.0001)

        let history = try #require(StubURLProtocol.requestHistory[path])
        #expect(history.count == 2)
        let secondQuery = history[1].url?.query ?? ""
        #expect(secondQuery.contains("page=page_2"))
    }

    /// Finding 2: a server that always reports has_more:true (with a fresh
    /// next_page every time) must not hang the refresh loop. Uses a single
    /// (non-queued) stubbed response, since the same has_more:true body is
    /// returned for every request regardless of the `page` query value.
    @Test func hardCapPreventsInfiniteLoopOnAlwaysMoreServer() async throws {
        let path = "/v1/organizations/cost_report"
        StubURLProtocol.requestHistory[path] = []
        StubURLProtocol.responseQueues[path] = []
        let alwaysMore = #"{"data":[{"starting_at":"2026-08-01T00:00:00Z","ending_at":"2026-08-02T00:00:00Z","results":[{"amount":"10.0","currency":"USD"}]}],"has_more":true,"next_page":"next"}"#
        StubURLProtocol.responses[path] = (200, Data(alwaysMore.utf8))

        let client = AdminCostClient(credentials: MockAdminCredentials(), session: stubbedSession())
        let snap = try await client.fetchMonthToDateCost(now: Date())

        // Loop must terminate (returning, not hanging) after exactly the
        // capped number of pages, summing only those pages' amounts.
        let history = try #require(StubURLProtocol.requestHistory[path])
        #expect(history.count == 12)
        // 12 pages x 10.0 cents = 1.20 USD
        #expect(abs(snap.monthToDateUSD - 1.20) < 0.0001)
    }
}
