import Testing
import Foundation
@testable import TokenMonitorKit

@Suite(.serialized) struct ModelCatalogClientTests {
    // swiftlint:disable:next line_length
    let body = #"{"data":[{"type":"model","id":"claude-fable-5","display_name":"Claude Fable 5","max_input_tokens":1000000,"max_tokens":128000},{"type":"model","id":"claude-haiku-4-5-20251001","display_name":"Claude Haiku 4.5","max_input_tokens":200000,"max_tokens":64000}],"has_more":false}"#

    @Test func fetchesAndDecodesContextWindows() async throws {
        StubURLProtocol.responses["/v1/models"] = (200, Data(body.utf8))
        let client = ModelCatalogClient(credentials: MockCredentials(), session: stubbedSession())
        let windows = try await client.fetchContextWindows()
        #expect(windows == ["claude-fable-5": 1_000_000, "claude-haiku-4-5-20251001": 200_000])

        let req = try #require(StubURLProtocol.lastRequests["/v1/models"])
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test func http401ThrowsStatusError() async {
        StubURLProtocol.responses["/v1/models"] = (401, Data())
        let client = ModelCatalogClient(credentials: MockCredentials(), session: stubbedSession())
        await #expect(throws: FetchError.httpStatus(401)) {
            _ = try await client.fetchContextWindows()
        }
    }

    @Test func missingCredentialsThrows() async {
        let client = ModelCatalogClient(credentials: MockCredentials(token: nil),
                                        session: stubbedSession())
        await #expect(throws: FetchError.credentialsUnavailable) {
            _ = try await client.fetchContextWindows()
        }
    }
}
