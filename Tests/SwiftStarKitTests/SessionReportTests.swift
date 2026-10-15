import Foundation
import Testing
@testable import SwiftStarKit

/// AN.4: ds4-engine's `report --json`, recorded on
/// `fixtures/sessions/20261013-123136-swiftstar`, as Analyze's Markdown.
struct SessionReportTests {
    private static let locale = Locale(identifier: "en_US")

    private static func markdown() throws -> String {
        try Fixtures.sessionReport().markdown(locale: locale)
    }

    /// The table rows of one `### Section`, up to the next heading.
    private static func rows(_ section: String, in text: String) -> [String] {
        let after = text.components(separatedBy: "### \(section)\n").dropFirst().first ?? ""
        let body = after.components(separatedBy: "\n### ").first ?? ""
        return body.split(separator: "\n").map(String.init).filter { $0.hasPrefix("| ") }
    }

    @Test func headerNamesSessionModelAndOutcome() throws {
        let first = try Self.markdown().split(separator: "\n").first.map(String.init)
        #expect(first == "**report**: 20261013-123136-swiftstar, qwen3.8-flash-next, ctx 20,000, 188s, answered")
    }

    @Test func failedAndRefusedCallsAreFlagged() throws {
        let flagged = Self.rows("Flagged steps", in: try Self.markdown())
        #expect(flagged.contains { $0.hasPrefix("| 2 | run ") && $0.contains("| failed: Tool error: unknown tool: run.") })
        #expect(flagged.contains { $0.hasPrefix("| 2 | run |") && $0.hasSuffix("| refused: unknown-tool |") })
    }

    @Test func loopGuardLabelIsFlagged() throws {
        let flagged = Self.rows("Flagged steps", in: try Self.markdown())
        #expect(flagged.contains("| — | — | loop guard fired: already_shown x2 |"))
    }

    @Test func syncsWithTokensAreListedWithLabels() throws {
        let prefill = Self.rows("Prefill", in: try Self.markdown())
        #expect(prefill.contains("| 2 | 1 | user | 45 | 794 ms | 56.7 tok/s | — |"))
        #expect(prefill.contains("| 2 | 5 | host_results | 32 | 104 ms | 306.3 tok/s | short batch, fixed cost |"))
    }

    @Test func emptySyncsAreCounted() throws {
        let text = try Self.markdown()
        #expect(!Self.rows("Prefill", in: text).contains { $0.contains("nothing new to prefill") })
        #expect(text.contains("19 syncs with nothing new to prefill are not listed."))
    }

    @Test func otherSchemaFails() {
        let r = SessionReport.decode(Data(#"{"schema": "ds4-session-report/2"}"#.utf8))
        guard case .failure(.malformed(let message)) = r else { Issue.record("expected malformed: \(r)"); return }
        #expect(message.contains("ds4-session-report/2"))
    }

    @Test func cellsEscapePipesAndNewlines() {
        #expect(SessionReport.cell("a | b\n  c") == #"a \| b c"#)
        #expect(SessionReport.cell(#"x\|y"#) == #"x\\\|y"#)
        #expect(SessionReport.cell(String(repeating: "z", count: 90), limit: 80).count == 80)
    }
}
