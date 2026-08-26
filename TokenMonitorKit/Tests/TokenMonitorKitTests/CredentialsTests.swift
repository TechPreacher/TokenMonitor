import Testing
import Foundation
@testable import TokenMonitorKit

@Suite struct CredentialsTests {
    @Test func extractsAccessToken() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"r","expiresAt":1756300000000}}"#
        let token = try ClaudeCredentialsFile.accessToken(fromJSON: Data(json.utf8))
        #expect(token == "sk-ant-oat01-abc")
    }

    @Test func malformedJSONThrows() {
        #expect(throws: CredentialError.malformed) {
            _ = try ClaudeCredentialsFile.accessToken(fromJSON: Data("{}".utf8))
        }
    }
}
