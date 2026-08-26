import Foundation

/// Scans ~/.claude/projects/**/*.jsonl and sums per-message token usage.
public struct TranscriptUsageReader: Sendable {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// One transcript line -> (timestamp, total tokens), or nil if not a usage line.
    static func tokens(inLine line: String) -> (timestamp: Date, tokens: Int)? {
        struct Line: Decodable {
            struct Message: Decodable {
                struct Usage: Decodable {
                    let inputTokens: Int?
                    let outputTokens: Int?
                    let cacheCreationInputTokens: Int?
                    let cacheReadInputTokens: Int?
                    enum CodingKeys: String, CodingKey {
                        case inputTokens = "input_tokens"
                        case outputTokens = "output_tokens"
                        case cacheCreationInputTokens = "cache_creation_input_tokens"
                        case cacheReadInputTokens = "cache_read_input_tokens"
                    }
                }
                let usage: Usage?
            }
            let timestamp: String?
            let message: Message?
        }
        guard let parsed = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)),
              let usage = parsed.message?.usage,
              let ts = parsed.timestamp,
              let date = Self.timestampFormatter.date(from: ts) else { return nil }
        let total = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
            + (usage.cacheCreationInputTokens ?? 0) + (usage.cacheReadInputTokens ?? 0)
        return (date, total)
    }

    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public func totals(now: Date, calendar: Calendar) throws -> TranscriptTotals {
        var today = 0
        var window = 0
        let windowStart = now.addingTimeInterval(-5 * 3600)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootDirectory,
                                             includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else {
            return TranscriptTotals(tokensToday: 0, tokensThisSessionWindow: 0, fetchedAt: now)
        }
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let (date, tokens) = Self.tokens(inLine: String(line)) else { continue }
                if calendar.isDate(date, inSameDayAs: now) { today += tokens }
                if date >= windowStart && date <= now { window += tokens }
            }
        }
        return TranscriptTotals(tokensToday: today, tokensThisSessionWindow: window, fetchedAt: now)
    }
}
