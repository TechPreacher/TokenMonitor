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
        let entrypoint: String?
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
            let entrypoint: String?
        }
        guard let parsed = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)),
              parsed.isSidechain != true,
              let usage = parsed.message?.usage,
              usage.inputTokens != nil else { return nil }
        let context = (usage.inputTokens ?? 0) + (usage.cacheCreationInputTokens ?? 0)
            + (usage.cacheReadInputTokens ?? 0)
        return ContextInfo(contextTokens: context, model: parsed.message?.model,
                           cwd: parsed.cwd, sessionId: parsed.sessionId,
                           entrypoint: parsed.entrypoint)
    }

    /// Live Models API catalog wins (exact id, then alias/dated-id prefix match);
    /// static fallback per docs (2026-08): 1M for the Claude 5 family and
    /// Opus/Sonnet 4.6+, 200k for Haiku and pre-4.6 models; "[1m]" beta suffix
    /// always means 1M.
    static func contextWindow(forModel model: String?, catalog: [String: Int] = [:]) -> Int {
        guard let model else { return 200_000 }
        if let window = catalog[model] { return window }
        if model.contains("[1m]") { return 1_000_000 }
        // Alias vs dated id: match in either direction, longest key wins.
        let prefixed = catalog.keys
            .filter { $0.hasPrefix(model) || model.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        if let prefixed, let window = catalog[prefixed] { return window }
        let millionTokenMarkers = ["fable", "mythos", "opus-5", "sonnet-5",
                                   "opus-4-6", "opus-4-7", "opus-4-8", "sonnet-4-6"]
        if millionTokenMarkers.contains(where: model.contains) { return 1_000_000 }
        return 200_000
    }

    public func sessions(now: Date, catalog: [String: Int] = [:]) throws -> [ActiveSession] {
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
            // Agent SDK sessions (claude-mem and other background helpers) share
            // the project's cwd and would show up as confusing duplicate rows.
            if info.entrypoint?.hasPrefix("sdk") == true { continue }
            let window = Self.contextWindow(forModel: info.model, catalog: catalog)
            let label = info.cwd.map { ($0 as NSString).lastPathComponent }
                ?? url.deletingLastPathComponent().lastPathComponent
            let percent = min(100, Double(info.contextTokens) / Double(window) * 100)
            sessions.append(ActiveSession(
                sessionId: info.sessionId ?? url.deletingPathExtension().lastPathComponent,
                label: label, contextTokens: info.contextTokens,
                windowTokens: window, percent: percent, lastActivity: mtime))
        }
        return Self.disambiguated(sessions.sorted { $0.lastActivity > $1.lastActivity })
    }

    /// Two live sessions in the same project share a label; suffix a short
    /// session-id so the rows stay tellable apart.
    private static func disambiguated(_ sessions: [ActiveSession]) -> [ActiveSession] {
        let labelCounts = Dictionary(grouping: sessions, by: \.label).mapValues(\.count)
        return sessions.map { session in
            guard labelCounts[session.label, default: 0] > 1 else { return session }
            return ActiveSession(sessionId: session.sessionId,
                                 label: "\(session.label) · \(session.sessionId.prefix(4))",
                                 contextTokens: session.contextTokens,
                                 windowTokens: session.windowTokens,
                                 percent: session.percent,
                                 lastActivity: session.lastActivity)
        }
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
