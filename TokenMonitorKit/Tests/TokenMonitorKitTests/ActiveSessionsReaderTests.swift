import Testing
import Foundation
@testable import TokenMonitorKit

@Suite struct ActiveSessionsReaderTests {
    // swiftlint:disable line_length
    static let usageLine = #"{"type":"assistant","timestamp":"2026-08-27T07:00:00.000Z","cwd":"/Users/me/Code/ProjectX","sessionId":"abc","message":{"model":"claude-fable-5","usage":{"input_tokens":2,"output_tokens":700,"cache_creation_input_tokens":5000,"cache_read_input_tokens":45000}}}"#
    static let laterUsageLine = #"{"type":"assistant","timestamp":"2026-08-27T07:05:00.000Z","cwd":"/Users/me/Code/ProjectX","sessionId":"abc","message":{"model":"claude-fable-5","usage":{"input_tokens":10,"output_tokens":100,"cache_creation_input_tokens":1000,"cache_read_input_tokens":99000}}}"#
    static let sidechainLine = #"{"type":"assistant","isSidechain":true,"timestamp":"2026-08-27T07:06:00.000Z","cwd":"/Users/me/Code/ProjectX","sessionId":"abc","message":{"model":"claude-fable-5","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1}}}"#
    static let millionModelLine = #"{"type":"assistant","timestamp":"2026-08-27T07:00:00.000Z","cwd":"/Users/me/Code/Big","sessionId":"def","message":{"model":"claude-sonnet-4-5[1m]","usage":{"input_tokens":0,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":500000}}}"#
    static let sdkLine = #"{"type":"assistant","entrypoint":"sdk-py","timestamp":"2026-08-27T07:00:00.000Z","cwd":"/Users/me/Code/ProjectX","sessionId":"sdk1","message":{"model":"claude-fable-5","usage":{"input_tokens":5,"output_tokens":5,"cache_creation_input_tokens":5,"cache_read_input_tokens":5}}}"#
    static let cliLine = #"{"type":"assistant","entrypoint":"cli","timestamp":"2026-08-27T07:00:00.000Z","cwd":"/Users/me/Code/ProjectX","sessionId":"cli2","message":{"model":"claude-fable-5","usage":{"input_tokens":2,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":20000}}}"#
    // swiftlint:enable line_length

    @Test func excludesSDKBackgroundSessions() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        // Same project dir: one interactive CLI session, one SDK helper session
        // (claude-mem etc.) — only the CLI session should be listed.
        try writeSession(root: root, project: "-Users-me-Code-ProjectX", file: "abc.jsonl",
                         lines: [Self.usageLine], mtime: now)
        try writeSession(root: root, project: "-Users-me-Code-ProjectX", file: "sdk1.jsonl",
                         lines: [Self.sdkLine], mtime: now)

        let sessions = try ActiveSessionsReader(rootDirectory: root).sessions(now: now)
        #expect(sessions.map(\.sessionId) == ["abc"])
    }

    @Test func duplicateLabelsGetShortIdSuffix() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        // Two genuine CLI sessions in the same project must stay distinguishable.
        try writeSession(root: root, project: "-Users-me-Code-ProjectX", file: "abc.jsonl",
                         lines: [Self.usageLine], mtime: now)
        try writeSession(root: root, project: "-Users-me-Code-ProjectX", file: "cli2.jsonl",
                         lines: [Self.cliLine], mtime: now.addingTimeInterval(-30))

        let sessions = try ActiveSessionsReader(rootDirectory: root).sessions(now: now)
        #expect(sessions.map(\.label) == ["ProjectX · abc", "ProjectX · cli2"])
    }

    @Test func parsesContextInfoFromUsageLine() throws {
        let info = try #require(ActiveSessionsReader.contextInfo(inLine: Self.usageLine))
        // context = input + cache_creation + cache_read (output excluded)
        #expect(info.contextTokens == 50002)
        #expect(info.model == "claude-fable-5")
        #expect(info.cwd == "/Users/me/Code/ProjectX")
        #expect(info.sessionId == "abc")
    }

    @Test func skipsSidechainMalformedAndNonUsageLines() {
        #expect(ActiveSessionsReader.contextInfo(inLine: Self.sidechainLine) == nil)
        #expect(ActiveSessionsReader.contextInfo(inLine: "garbage") == nil)
        #expect(ActiveSessionsReader.contextInfo(inLine: #"{"type":"user","cwd":"/x"}"#) == nil)
    }

    @Test func contextWindowMapping() {
        #expect(ActiveSessionsReader.contextWindow(forModel: "claude-fable-5") == 200_000)
        #expect(ActiveSessionsReader.contextWindow(forModel: "claude-sonnet-4-5[1m]") == 1_000_000)
        #expect(ActiveSessionsReader.contextWindow(forModel: nil) == 200_000)
    }

    @Test func listsActiveSessionsWithPercentAndLabel() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()

        // Active session: recent mtime, two usage lines -> last one wins.
        try writeSession(root: root, project: "-Users-me-Code-ProjectX", file: "abc.jsonl",
                         lines: [Self.usageLine, Self.laterUsageLine, Self.sidechainLine, "junk"],
                         mtime: now.addingTimeInterval(-60))
        // Stale session: mtime beyond 5-minute activity window -> excluded.
        try writeSession(root: root, project: "-Users-me-Code-Old", file: "old.jsonl",
                         lines: [Self.usageLine], mtime: now.addingTimeInterval(-3600))

        let reader = ActiveSessionsReader(rootDirectory: root)
        let sessions = try reader.sessions(now: now)

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.sessionId == "abc")
        #expect(session.label == "ProjectX")
        #expect(session.contextTokens == 100_010)
        #expect(session.windowTokens == 200_000)
        #expect(abs(session.percent - 50.005) < 0.01)
    }

    @Test func millionTokenWindowPercent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        try writeSession(root: root, project: "-Users-me-Code-Big", file: "def.jsonl",
                         lines: [Self.millionModelLine], mtime: now)

        let sessions = try ActiveSessionsReader(rootDirectory: root).sessions(now: now)
        let session = try #require(sessions.first)
        #expect(session.windowTokens == 1_000_000)
        #expect(abs(session.percent - 50.0) < 0.01)
    }

    @Test func sortsByMostRecentActivityFirst() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        try writeSession(root: root, project: "-A", file: "one.jsonl",
                         lines: [Self.usageLine], mtime: now.addingTimeInterval(-120))
        try writeSession(root: root, project: "-B", file: "two.jsonl",
                         lines: [Self.millionModelLine], mtime: now.addingTimeInterval(-10))

        let sessions = try ActiveSessionsReader(rootDirectory: root).sessions(now: now)
        #expect(sessions.map(\.sessionId) == ["def", "abc"])
    }

    @Test func emptyWhenRootMissing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let sessions = try ActiveSessionsReader(rootDirectory: missing).sessions(now: Date())
        #expect(sessions.isEmpty)
    }

    // MARK: - helpers

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSession(root: URL, project: String, file: String,
                              lines: [String], mtime: Date) throws {
        let dir = root.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }
}
