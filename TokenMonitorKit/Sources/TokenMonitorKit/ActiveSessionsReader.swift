import Foundation

/// Finds Claude Code sessions with recent transcript writes and reports how
/// full each session's context window is, from the newest usage entry in its
/// ~/.claude/projects/<project>/<session>.jsonl file.
public struct ActiveSessionsReader: Sendable {
    /// Newest usage entry of one transcript line.
    struct ContextInfo {
        let contextTokens: Int
        let model: String?
        let cwd: String?
        let sessionId: String?
    }

    private let rootDirectory: URL
    /// A session counts as active if its file was written within this interval.
    private let activityWindow: TimeInterval
    /// Only the file tail is scanned for the newest usage entry.
    private static let tailBytes = 256 * 1024

    public init(rootDirectory: URL, activityWindow: TimeInterval = 300) {
        self.rootDirectory = rootDirectory
        self.activityWindow = activityWindow
    }

    static func contextInfo(inLine line: String) -> ContextInfo? {
        struct Line: Decodable {
            struct Message: Decodable {
                struct Usage: Decodable {
                    let inputTokens: Int?
                    let cacheCreationInputTokens: Int?
                    let cacheReadInputTokens: Int?
                    enum CodingKeys: String, CodingKey {
                        case inputTokens = "input_tokens"
                        case cacheCreationInputTokens = "cache_creation_input_tokens"
                        case cacheReadInputTokens = "cache_read_input_tokens"
                    }
                }
                let usage: Usage?
                let model: String?
            }
            let message: Message?
            let cwd: String?
            let sessionId: String?
            let isSidechain: Bool?
        }
        guard let parsed = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)),
              parsed.isSidechain != true,
              let usage = parsed.message?.usage,
              usage.inputTokens != nil else { return nil }
        let context = (usage.inputTokens ?? 0) + (usage.cacheCreationInputTokens ?? 0)
            + (usage.cacheReadInputTokens ?? 0)
        return ContextInfo(contextTokens: context, model: parsed.message?.model,
                           cwd: parsed.cwd, sessionId: parsed.sessionId)
    }

    static func contextWindow(forModel model: String?) -> Int {
        if let model, model.contains("[1m]") { return 1_000_000 }
        return 200_000
    }

    public func sessions(now: Date) throws -> [ActiveSession] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var sessions: [ActiveSession] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
                  now.timeIntervalSince(mtime) <= activityWindow,
                  let info = Self.newestContextInfo(inFileAt: url) else { continue }
            let window = Self.contextWindow(forModel: info.model)
            let label = info.cwd.map { ($0 as NSString).lastPathComponent }
                ?? url.deletingLastPathComponent().lastPathComponent
            let percent = min(100, Double(info.contextTokens) / Double(window) * 100)
            sessions.append(ActiveSession(
                sessionId: info.sessionId ?? url.deletingPathExtension().lastPathComponent,
                label: label, contextTokens: info.contextTokens,
                windowTokens: window, percent: percent, lastActivity: mtime))
        }
        return sessions.sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func newestContextInfo(inFileAt url: URL) -> ContextInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return nil }
        // Lossy decode on purpose: the tail cut can split a multibyte character,
        // which would make a failable String init drop the whole chunk.
        // swiftlint:disable:next optional_data_string_conversion
        let tail = String(decoding: data, as: UTF8.self)
        for line in tail.split(separator: "\n").reversed() {
            if let info = contextInfo(inLine: String(line)) { return info }
        }
        return nil
    }
}
