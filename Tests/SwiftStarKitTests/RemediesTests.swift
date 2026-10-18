import Foundation
import Testing
@testable import SwiftStarKit

/// AN.3: remedies the analysis model proposes in an `agents-md` block, the
/// engine's suggestions beside them, and the instructions file they go to.
struct RemediesTests {
    private static func rows(_ texts: [String], answer: String? = nil) -> [TranscriptRow] {
        texts.map { TranscriptRow.narration($0) }
            + (answer.map { [.answer(EngineAnswer(text: $0, contextUsed: nil, contextSize: nil, durationMs: nil))] } ?? [])
    }

    // The 27B's live answer (2026-10-18): the block is in its narration.
    @Test func parseFindsTheLiveBlock() throws {
        var t = EngineTranscript()
        try Fixtures.events("analysis-remedies.ndjson").forEach { t.apply($0) }
        let lines = Remedies.parse(rows: t.rows, from: 0)
        #expect(lines.count == 3)
        #expect(lines.first?.hasPrefix("- Only call tools that exist in the provided toolset") == true)
    }

    @Test func noBlockNoRemedies() {
        #expect(Remedies.parse(rows: Self.rows(["Prose only.\n\n```swift\nlet x = 1\n```"]), from: 0).isEmpty)
    }

    @Test func lastBlockWins() {
        let rows = Self.rows(["```agents-md\n- old\n```", "Better:\n\n```agents-md\n- new one\n\n- new two\n```"])
        #expect(Remedies.parse(rows: rows, from: 0) == ["- new one", "- new two"])
    }

    @Test func aBlockInTheAnswersReplyCounts() {
        let rows: [TranscriptRow] = [.answer(
            EngineAnswer(text: "summary", contextUsed: nil, contextSize: nil, durationMs: nil),
            reply: "```agents-md\n- from the reply\n```")]
        #expect(Remedies.parse(rows: rows, from: 0) == ["- from the reply"])
    }

    @Test func blockBeforeTheForkIsIgnored() {
        let rows = Self.rows(["```agents-md\n- before the fork\n```", "no block here"])
        #expect(Remedies.parse(rows: rows, from: 1).isEmpty)
    }

    @Test func mergedDedupesAndMarks() {
        let remedies = Remedies.merged(
            model: ["- Run the tests with `swift test`.", "- New rule."],
            engine: [(line: "+- Run the tests with `swift test`.", why: "2 test runs failed"),
                     (line: "+- `a.swift` is read often; see it before searching.", why: "read 4 times")],
            existing: "# Rules\n\n- New rule.\n")
        #expect(remedies.map(\.line) == [
            "- Run the tests with `swift test`.", "- New rule.", "- `a.swift` is read often; see it before searching.",
        ])
        #expect(remedies[0].fromEngine == "2 test runs failed")
        #expect(remedies[1].alreadyThere)
        #expect(!remedies[0].alreadyThere)
        #expect(remedies[2].fromEngine == "read 4 times")
    }

    @Test func appliedAddsTheHeadingOnce() {
        let first = Remedies.applied(to: nil, lines: ["- one"])
        #expect(first == "## From Analyze\n\n- one\n")
        let second = Remedies.applied(to: "# Project\n\nIntro.\n\n" + first, lines: ["- two", "- one"])
        #expect(second == "# Project\n\nIntro.\n\n## From Analyze\n\n- one\n- two\n")
        #expect(Remedies.applied(to: "# Project", lines: ["- one"]) == "# Project\n\n## From Analyze\n\n- one\n")
    }

    @Test func fileChoice() {
        #expect(Remedies.file(agentsExists: true, claudeExists: true) == "AGENTS.md")
        #expect(Remedies.file(agentsExists: false, claudeExists: true) == "CLAUDE.md")
        #expect(Remedies.file(agentsExists: false, claudeExists: false) == "AGENTS.md")
    }

    @Test func doneTitle() {
        #expect(Remedies.doneTitle(count: 0, file: "AGENTS.md") == "Done")
        #expect(Remedies.doneTitle(count: 1, file: "AGENTS.md") == "Done · add 1 line to AGENTS.md")
        #expect(Remedies.doneTitle(count: 2, file: "CLAUDE.md") == "Done · add 2 lines to CLAUDE.md")
    }
}
