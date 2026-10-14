import Testing
@testable import SwiftStarKit

struct PromptHistoryTests {
    private let entries = ["first", "second", "third"]

    @Test func entriesAreTypedPromptsWithoutAnalyzeOrRepeats() {
        let rows: [TranscriptRow] = [
            .divider("Resumed"),
            .user("first"),
            .answer(EngineAnswer(text: "ok", contextUsed: nil, contextSize: nil, durationMs: nil)),
            .user("/model qwen"),
            .user("/model qwen"),
            .system("Switched."),
            .user(EngineAnalysis.promptShown),
            // A relaunched fork rebuilds the full Analyze prompt.
            .user(EngineAnalysis.prompt(report: "## Report")),
            .user("first"),
        ]
        #expect(PromptHistory.entries(from: rows) == ["first", "/model qwen", "first"])
    }

    @Test func upStepsOlderAndStopsAtTheOldest() {
        var h = PromptHistory()
        #expect(h.up(current: "", entries: entries) == "third")
        #expect(h.up(current: "third", entries: entries) == "second")
        #expect(h.up(current: "second", entries: entries) == "first")
        #expect(h.up(current: "first", entries: entries) == "first")
    }

    @Test func downStepsNewerThenClears() {
        var h = PromptHistory()
        _ = h.up(current: "", entries: entries)
        _ = h.up(current: "third", entries: entries)
        #expect(h.down(current: "second", entries: entries) == "third")
        #expect(h.down(current: "third", entries: entries) == "")
        #expect(h.down(current: "", entries: entries) == nil)
    }

    @Test func downWithoutRecallMovesTheCursor() {
        var h = PromptHistory()
        #expect(h.down(current: "", entries: entries) == nil)
    }

    @Test func anEditedFieldKeepsItsArrows() {
        var h = PromptHistory()
        #expect(h.up(current: "a draft", entries: entries) == nil)
        _ = h.up(current: "", entries: entries)
        #expect(h.up(current: "third, edited", entries: entries) == nil)
        #expect(h.down(current: "third, edited", entries: entries) == nil)
    }

    @Test func anEmptiedFieldStartsFromTheNewest() {
        var h = PromptHistory()
        _ = h.up(current: "", entries: entries)
        _ = h.up(current: "third", entries: entries)
        #expect(h.up(current: "", entries: entries) == "third")
    }

    @Test func noEntriesMovesTheCursor() {
        var h = PromptHistory()
        #expect(h.up(current: "", entries: []) == nil)
        #expect(h.down(current: "", entries: []) == nil)
    }
}
