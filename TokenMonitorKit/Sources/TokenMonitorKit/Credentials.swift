import Foundation
import Security

public enum CredentialError: Error, Equatable {
    case notFound
    case malformed
}

public protocol CredentialStore: Sendable {
    /// Claude Code's own OAuth access token (read-only; Keychain then file fallback).
    func readClaudeCodeOAuthToken() throws -> String
    /// Admin API key the user pasted into Settings. nil if never configured.
    func readAdminAPIKey() -> String?
    func writeAdminAPIKey(_ key: String) throws
}

public enum ClaudeCredentialsFile {
    public static func accessToken(fromJSON data: Data) throws -> String {
        struct Wrapper: Decodable {
            struct OAuth: Decodable { let accessToken: String }
            let claudeAiOauth: OAuth
        }
        guard let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            throw CredentialError.malformed
        }
        return wrapper.claudeAiOauth.accessToken
    }
}

/// Real Keychain-backed store. Not unit-tested (requires the login keychain);
/// keep it a thin shell over tested `ClaudeCredentialsFile`.
public struct KeychainCredentialStore: CredentialStore {
    public init() {}

    public func readClaudeCodeOAuthToken() throws -> String {
        if let data = Self.genericPassword(service: "Claude Code-credentials") {
            return try ClaudeCredentialsFile.accessToken(fromJSON: data)
        }
        // Fallback: ~/.claude/.credentials.json
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { throw CredentialError.notFound }
        return try ClaudeCredentialsFile.accessToken(fromJSON: data)
    }

    private static let adminService = "com.techpreacher.TokenMonitor"
    private static let adminAccount = "admin-api-key"

    public func readAdminAPIKey() -> String? {
        guard let data = Self.genericPassword(service: Self.adminService, account: Self.adminAccount),
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    public func writeAdminAPIKey(_ key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.adminService,
            kSecAttrAccount as String: Self.adminAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.malformed }
    }

    private static func genericPassword(service: String, account: String? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
