import Testing
import Foundation
@testable import TokenMonitorKit

@Suite struct TranscriptUsageReaderTests {
    let assistantLine = #"{"type":"assistant","timestamp":"2026-08-26T10:00:00.000Z","message":{"usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}"#

    @Test func parsesTokensFromAssistantLine() throws {
        let parsed = try #require(TranscriptUsageReader.tokens(inLine: assistantLine))
        #expect(parsed.tokens == 135)
    }

    @Test func skipsMalformedAndNonUsageLines() {
        #expect(TranscriptUsageReader.tokens(inLine: "not json at all") == nil)
        #expect(TranscriptUsageReader.tokens(inLine: #"{"type":"user","timestamp":"2026-08-26T10:00:00.000Z"}"#) == nil)
    }

    @Test func sumsAcrossFilesAndBucketsCorrectly() throws {
        // Build temp tree: root/projA/x.jsonl, root/projB/y.jsonl
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projA = root.appendingPathComponent("projA")
        let projB = root.appendingPathComponent("projB")
        try FileManager.default.createDirectory(at: projA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // now = 2026-08-26T12:00:00Z. Line1: 10:00 today (in 5h window).
        // Line2: 06:00 today (today, outside 5h window). Line3: yesterday (neither).
        let line2 = #"{"type":"assistant","timestamp":"2026-08-26T06:00:00.000Z","message":{"usage":{"input_tokens":1,"output_tokens":1}}}"#
        let line3 = #"{"type":"assistant","timestamp":"2026-08-25T10:00:00.000Z","message":{"usage":{"input_tokens":1000,"output_tokens":0}}}"#
        try (assistantLine + "\n" + line2).write(
            to: projA.appendingPathComponent("x.jsonl"), atomically: true, encoding: .utf8)
        try (line3 + "\nnot json\n").write(
            to: projB.appendingPathComponent("y.jsonl"), atomically: true, encoding: .utf8)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!

        let totals = try TranscriptUsageReader(rootDirectory: root)
            .totals(now: now, calendar: utc)
        #expect(totals.tokensToday == 135 + 2)          // both today-lines
        #expect(totals.tokensThisSessionWindow == 135)  // only the 10:00 line
    }

    @Test func missingRootYieldsZeroTotals() throws {
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let totals = try TranscriptUsageReader(rootDirectory: ghost)
            .totals(now: .now, calendar: .current)
        #expect(totals.tokensToday == 0)
    }
}
