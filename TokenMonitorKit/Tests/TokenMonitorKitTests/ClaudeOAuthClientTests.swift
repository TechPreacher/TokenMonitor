import Testing
import Foundation
@testable import TokenMonitorKit

struct MockCredentials: CredentialStore {
    var token: String? = "sk-ant-oat01-test"
    func readClaudeCodeOAuthToken() throws -> String {
        guard let token else { throw CredentialError.notFound }
        return token
    }
    func readAdminAPIKey() -> String? { nil }
    func writeAdminAPIKey(_ key: String) throws {}
}

@Suite(.serialized) struct ClaudeOAuthClientTests {
    @Test func fetchesAndDecodesUsage() async throws {
        let body = #"{"five_hour":{"utilization":42.0,"resets_at":null},"seven_day":{"utilization":10.0,"resets_at":null}}"#
        StubURLProtocol.responses["/api/oauth/usage"] = (200, Data(body.utf8))
        let client = ClaudeOAuthClient(credentials: MockCredentials(), session: stubbedSession())
        let snap = try await client.fetchUsage()
        #expect(snap.sessionPercent == 42.0)
        // Verify auth headers were sent
        let req = try #require(StubURLProtocol.lastRequests["/api/oauth/usage"])
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test func http401ThrowsStatusError() async {
        StubURLProtocol.responses["/api/oauth/usage"] = (401, Data())
        let client = ClaudeOAuthClient(credentials: MockCredentials(), session: stubbedSession())
        await #expect(throws: FetchError.httpStatus(401)) {
            _ = try await client.fetchUsage()
        }
    }

    @Test func missingCredentialsThrows() async {
        let client = ClaudeOAuthClient(credentials: MockCredentials(token: nil), session: stubbedSession())
        await #expect(throws: FetchError.credentialsUnavailable) {
            _ = try await client.fetchUsage()
        }
    }
}
