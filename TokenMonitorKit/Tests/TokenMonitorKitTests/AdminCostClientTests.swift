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
}
