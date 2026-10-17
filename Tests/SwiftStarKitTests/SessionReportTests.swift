import Foundation
import Testing
@testable import SwiftStarKit

/// AN.4: ds4-engine's `report --json` (`ds4-session-report/2`), recorded on
/// `fixtures/sessions/20261013-123136-swiftstar`, as Analyze's Markdown.
struct SessionReportTests {
    private static let locale = Locale(identifier: "en_US")

    private static func markdown() throws -> String {
        try Fixtures.sessionReport().markdown(locale: locale)
    }

    /// The fixture with `edit` applied to its JSON, for what the recorded
    /// session doesn't hold: an unanswered prompt, an engine error, a
    /// conversation-state load.
    private static func markdown(editing edit: (inout [String: Any]) -> Void) throws -> String {
        let data = try Data(contentsOf: Fixtures.root.appendingPathComponent("report.json"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&json)
        let edited = try JSONSerialization.data(withJSONObject: json)
        return try SessionReport.decode(edited).get().markdown(locale: locale)
    }

    /// Sets `key` on prompt `index`'s turn (0-based) in a report's JSON.
    private static func setTurn(_ json: inout [String: Any], _ index: Int, _ key: String, _ value: Any) {
        guard var turns = json["turns"] as? [[String: Any]] else { return }
        turns[index][key] = value
        json["turns"] = turns
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

    @Test func loopGuardNoticesAreFlaggedOnTheirCalls() throws {
        let flagged = Self.rows("Flagged steps", in: try Self.markdown())
        #expect(flagged.contains("| 4 | read Sources/SwiftStarKit/Severity.swift | loop guard: already_shown |"))
        #expect(flagged.contains("| 4 | read Sources/SwiftStarKit/PathAbbreviation.swift | loop guard: already_shown |"))
        #expect(flagged.contains("| — | — | loop guard fired: already_shown x2 |"))
    }

    @Test func unansweredPromptIsFlagged() throws {
        let text = try Self.markdown {
            Self.setTurn(&$0, 1, "answered", false)
            Self.setTurn(&$0, 1, "interrupted", true)
        }
        #expect(Self.rows("Flagged steps", in: text).contains("| 2 | — | no answer (interrupted) |"))
    }

    @Test func engineErrorsAreFlagged() throws {
        let text = try Self.markdown {
            Self.setTurn(&$0, 2, "errors", [["label": "engine call run_until_pause ended: failed"]])
        }
        #expect(Self.rows("Flagged steps", in: text).contains("| 3 | — | engine call run_until_pause ended: failed |"))
    }

    @Test func sessionRowsShowChainStartupAndState() throws {
        let session = Self.rows("Session", in: try Self.markdown())
        #expect(session.contains(
            "| Continues | 20261013-122439-swiftstar (3 prompts), 20261013-122106-swiftstar (1 of 4 prompts kept) |"))
        #expect(session.contains("| Start-up | candidate ready 17s · index primed 3.3s |"))
        #expect(session.contains("| Ending | 0 files changed · closed · telemetry ok · 0 engine errors |"))
        #expect(session.contains("| DFlash | off (no drafter) |"))
    }

    @Test func prefixCacheRowIsTheEngineLabel() throws {
        let session = Self.rows("Session", in: try Self.markdown())
        #expect(session.contains(
            "| Prefix cache | prompt 1: prefix-cache miss: 944 tokens filled, 1.75 s spent; what changed was not recorded |"))
    }

    @Test func conversationStateIsShown() throws {
        let text = try Self.markdown {
            $0["conversation_state"] = [[
                "prompt": 1, "outcome": "loaded", "bytes": 365_000_000, "load_ms": 1200.0,
                "label": "conversation state loaded",
            ]]
        }
        #expect(Self.rows("Session", in: text).contains(
            "| Conversation state | prompt 1: conversation state loaded, 0.3 GiB in 1.2s |"))
    }

    @Test func signalsAreRaw() throws {
        let text = try Self.markdown()
        #expect(text.contains("- result bytes: 8,997 total, 8,997 shown"))
        #expect(text.contains("- constraint: masked_token_count 0 · forbidden_argmax 0 · removed_probability_mass []"))
    }

    @Test func notesAreShown() throws {
        #expect(try Self.markdown().contains("- a prefix-cache miss here predates recording which part of the key changed"))
    }

    @Test func syncsWithTokensAreListedWithLabels() throws {
        let prefill = Self.rows("Prefill", in: try Self.markdown())
        #expect(prefill.contains("| 2 | 1 | user | 45 | 794 ms | 56.7 tok/s | short batch, two tiles, fixed cost |"))
        #expect(prefill.contains("| 2 | 5 | host_results | 32 | 104 ms | 306.3 tok/s | short batch, fixed cost |"))
        #expect(prefill.contains("| 2 | 3 | host_results | 78 | 219 ms | 356.8 tok/s | — |"))
    }

    @Test func emptySyncsAreCounted() throws {
        let text = try Self.markdown()
        #expect(!Self.rows("Prefill", in: text).contains { $0.contains("nothing new to prefill") })
        #expect(text.contains("19 syncs with nothing new to prefill are not listed."))
    }

    @Test func otherSchemaFails() {
        let r = SessionReport.decode(Data(#"{"schema": "ds4-session-report/1"}"#.utf8))
        guard case .failure(.malformed(let message)) = r else { Issue.record("expected malformed: \(r)"); return }
        #expect(message.contains("ds4-session-report/1"))
    }

    @Test func cellsEscapePipesAndNewlines() {
        #expect(SessionReport.cell("a | b\n  c") == #"a \| b c"#)
        #expect(SessionReport.cell(#"x\|y"#) == #"x\\\|y"#)
        #expect(SessionReport.cell(String(repeating: "z", count: 90), limit: 80).count == 80)
    }
}
