import Foundation

public enum FetchError: Error, Equatable {
    case httpStatus(Int)
    case credentialsUnavailable
    case decoding
}

public protocol UsageProviding: Sendable {
    func fetchUsage() async throws -> UsageSnapshot
}

/// Reads Claude Code's OAuth token and calls the (undocumented) usage endpoint.
public struct ClaudeOAuthClient: UsageProviding {
    private let credentials: CredentialStore
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(credentials: CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        guard let token = try? credentials.readClaudeCodeOAuthToken() else {
            throw FetchError.credentialsUnavailable
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.decoding }
        guard http.statusCode == 200 else { throw FetchError.httpStatus(http.statusCode) }
        guard let decoded = try? OAuthUsageResponse.decode(from: data) else {
            throw FetchError.decoding
        }
        return decoded.snapshot(fetchedAt: Date())
    }
}
