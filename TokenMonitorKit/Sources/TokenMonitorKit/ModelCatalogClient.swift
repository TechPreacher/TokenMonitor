import Foundation

public protocol ModelCatalogProviding: Sendable {
    /// Model id -> context window (max input tokens).
    func fetchContextWindows() async throws -> [String: Int]
}

/// Fetches per-model context windows from the Models API using Claude Code's
/// OAuth token (verified working with `anthropic-beta: oauth-2025-04-20`).
public struct ModelCatalogClient: ModelCatalogProviding {
    private let credentials: CredentialStore
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/models?limit=100")!

    public init(credentials: CredentialStore, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetchContextWindows() async throws -> [String: Int] {
        guard let token = try? credentials.readClaudeCodeOAuthToken() else {
            throw FetchError.credentialsUnavailable
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.decoding }
        guard http.statusCode == 200 else { throw FetchError.httpStatus(http.statusCode) }

        struct ModelList: Decodable {
            struct Model: Decodable {
                let id: String
                let maxInputTokens: Int?
                enum CodingKeys: String, CodingKey {
                    case id
                    case maxInputTokens = "max_input_tokens"
                }
            }
            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw FetchError.decoding
        }
        return list.data.reduce(into: [:]) { windows, model in
            if let window = model.maxInputTokens { windows[model.id] = window }
        }
    }
}
