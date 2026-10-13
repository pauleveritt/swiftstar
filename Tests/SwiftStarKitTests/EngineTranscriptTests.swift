import Testing
import Foundation
@testable import SwiftStarKit

struct EngineTranscriptTests {
    private func cards(_ t: EngineTranscript) -> [EngineToolCard] {
        t.rows.compactMap { if case .tool(let c) = $0 { c } else { nil } }
    }

    @Test func toolReadFixtureBuildsRows() throws {
        var t = EngineTranscript()
        t.appendUser("go")
        for e in try Fixtures.events("tool-read.ndjson") { t.apply(e) }
        let cs = cards(t)
        #expect(cs.count == 1)
        #expect(cs.allSatisfy { $0.ok == true && $0.result != nil })
        #expect(t.rows.filter { if case .answer = $0 { true } else { false } }.count == 1)
        #expect(!t.isBusy && !t.isGenerating && !t.isAwaitingInput)
    }

    @Test func transcriptKeepsSessionInfo() throws {
        var t = EngineTranscript()
        #expect(t.session == nil)
        var sawSession = false
        for e in try Fixtures.events("tool-read.ndjson") {
            t.apply(e)
            if case .session = e {
                sawSession = true
                #expect(t.session?.modelID == "qwen3.8-27b")
                #expect(t.session?.contextSize == 20000)
            }
        }
        #expect(sawSession)
        t.apply(.closed(capturePath: nil))
        #expect(t.session == nil)
    }

    @Test func repeatedReadsGetOwnResults() {
        let tool = EngineTool(op: "read", path: "a")
        let res = EngineToolResult(tool: tool, preview: "p", truncated: false)
        var t = EngineTranscript()
        for _ in 0..<2 {
            t.apply(.toolStart(tool))
            t.apply(.toolEnd(tool, ok: true, durationMs: 1))
            t.apply(.toolResult(res))
        }
        let cs = cards(t)
        #expect(cs.count == 2)
        #expect(cs.allSatisfy { $0.ok == true && $0.result == res })
    }

    @Test func unmatchedToolEndAndResultAreIgnored() {
        // A toolEnd/toolResult with no preceding toolStart for that tool
        // (op+path) is dropped, not crashed on or shown as a phantom card.
        let tool = EngineTool(op: "read", path: "a")
        var t = EngineTranscript()
        t.apply(.toolEnd(tool, ok: true, durationMs: 1))
        t.apply(.toolResult(EngineToolResult(tool: tool, preview: "p", truncated: false)))
        #expect(cards(t).isEmpty)
        #expect(t.rows.isEmpty)
    }

    @Test func promptEventDoesNotDuplicateUserRow() {
        var t = EngineTranscript()
        t.appendUser("x")
        t.apply(.prompt("x"))
        #expect(t.rows == [.user("x")])
    }

    @Test func busyAcrossToolCalls() throws {
        var t = EngineTranscript()
        var started = false
        var sawGeneratingFlip = false
        for e in try Fixtures.events("tool-read.ndjson") {
            t.apply(e)
            if case .prompt = e { started = true }
            if case .awaitingInput = e, started { break }
            if started {
                #expect(t.isBusy)
                if !t.isGenerating { sawGeneratingFlip = true }
            }
        }
        #expect(sawGeneratingFlip)
        #expect(!t.isBusy)
    }

    @Test func loadingTextClearedOnFirstInput() {
        var t = EngineTranscript()
        t.apply(.loading("Loading model"))
        #expect(t.loadingText == "Loading model")
        t.apply(.awaitingInput)
        #expect(t.loadingText == nil)
    }

    @Test func stopDisabledWhenAwaitingInput() {
        var t = EngineTranscript()
        t.apply(.awaitingInput)
        #expect(!t.isBusy)
        t.appendUser("hi")
        #expect(!t.isBusy)
        t.apply(.prompt("hi"))
        #expect(t.isBusy)
    }

    @Test func interruptedAddsStoppedRow() throws {
        var t = EngineTranscript()
        t.appendUser("go")
        for e in try Fixtures.events("stop.ndjson") { t.apply(e) }
        #expect(t.rows.last == .system("Stopped."))
        let before = t.rows.dropLast().last
        if case .system = before { Issue.record("row before Stopped is system") }
        #expect(!t.rows.contains { if case .answer = $0 { true } else { false } })
    }

    @Test func noticeAndRefusalRows() {
        var t = EngineTranscript()
        t.apply(.notice("h"))
        t.apply(.refused("r"))
        #expect(t.rows == [.system("h"), .error("r")])
    }
}

struct EngineTranscriptPendingTests {
    @Test func stopDisabledWhileQueued() {
        var t = EngineTranscript()
        t.appendUser("x")
        #expect(!t.isBusy)
    }

    @Test func busyStartsOnPromptEvent() {
        var t = EngineTranscript()
        t.appendUser("x")
        t.apply(.prompt("x"))
        #expect(t.isBusy)
        #expect(t.pendingUserCount == 0)
    }

    @Test func commandRowIsNotLeftPending() {
        var t = EngineTranscript()
        t.appendUser("/help")
        t.apply(.notice("commands: ..."))
        t.apply(.awaitingInput)
        #expect(t.pendingUserCount == 0)
        #expect(!t.isPending(rowAt: 0))
    }

    @Test func pendingClearsOnError() {
        var t = EngineTranscript()
        t.appendUser("x")
        #expect(t.isPending(rowAt: 0))
        t.apply(.error("queue full"))
        #expect(t.pendingUserCount == 0)
        #expect(!t.isBusy)
    }

    @Test func pendingSurvivesLoadingAndGenerating() {
        var t = EngineTranscript()
        t.appendUser("x")
        t.apply(.loading("mapping"))
        t.apply(.generating(true))
        #expect(t.isPending(rowAt: 0))
    }

    @Test func endClearsEverything() {
        var t = EngineTranscript()
        t.appendUser("x")
        t.apply(.prompt("x"))
        t.appendUser("y")
        t.end()
        #expect(!t.isBusy && !t.isGenerating && !t.isAwaitingInput)
        #expect(t.loadingText == nil && t.pendingUserCount == 0)
    }

    @Test func errorMidTurnKeepsStop() {
        var t = EngineTranscript()
        t.apply(.prompt("x"))
        t.apply(.error("queue full"))
        #expect(t.isBusy)
    }

    @Test func closedAndRefusedClearPending() {
        var a = EngineTranscript()
        a.appendUser("x")
        a.apply(.closed(capturePath: nil))
        #expect(a.pendingUserCount == 0)
        var b = EngineTranscript()
        b.appendUser("x")
        b.apply(.refused("no"))
        #expect(b.pendingUserCount == 0)
    }

    @Test func promptClearsSeveralPending() {
        var t = EngineTranscript()
        t.appendUser("a")
        t.appendUser("b")
        #expect(t.pendingUserCount == 2)
        t.apply(.prompt("a\n\nb"))
        #expect(t.pendingUserCount == 0)
    }

    @Test func pauseAndMemoryLeavePending() {
        var t = EngineTranscript()
        t.appendUser("a")
        t.apply(.pause(PauseMetrics(prefillTokens: 1, prefillMs: 1, evalCount: 1, evalMs: 1)))
        t.apply(.memory(EngineMemory(allocatedBytes: 1, budgetBytes: 2, planGiB: nil)))
        #expect(t.isPending(rowAt: 0))
    }

    @Test func queuedMarksPendingRow() {
        var t = EngineTranscript()
        t.appendUser("x")
        #expect(!t.isQueued(rowAt: 0))
        t.apply(.queued(count: 1))
        #expect(t.isQueued(rowAt: 0))
        #expect(t.isPending(rowAt: 0))
    }

    @Test func steeringClearsAllPendingAndNotes() {
        var t = EngineTranscript()
        t.appendUser("a")
        t.appendUser("b")
        t.apply(.queued(count: 2))
        t.apply(.steering(applied: true))
        #expect(t.pendingUserCount == 0)
        #expect(t.queuedUserRows.isEmpty)
        #expect(t.rows.last == .system("Queued message delivered"))
        t.apply(.steering(applied: false))
        #expect(t.rows.last == .system("Queued message not confirmed"))
    }
}

struct EngineTranscriptSurfaceTests {
    @Test func emptyAnswerShowsReason() {
        var t = EngineTranscript()
        t.apply(.answer(EngineAnswer(text: "", contextUsed: 1, contextSize: 2, durationMs: nil, reason: "ran out of tokens")))
        #expect(t.rows.last == .error("No answer: ran out of tokens"))
    }

    @Test func emptyAnswerWithoutReasonHasFallback() {
        var t = EngineTranscript()
        t.apply(.answer(EngineAnswer(text: "", contextUsed: nil, contextSize: nil, durationMs: nil)))
        #expect(t.rows.last == .error("No answer — the model stopped without answering"))
    }

    @Test func nonEmptyAnswerStaysAnAnswer() {
        var t = EngineTranscript()
        let a = EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil)
        t.apply(.answer(a))
        #expect(t.rows.last == .answer(a))
    }

    @Test func summaryJoinsDurationAndContext() {
        let a = EngineAnswer(text: "hi", contextUsed: 420, contextSize: 8192, durationMs: 1234)
        #expect(a.summary(locale: Locale(identifier: "en_US")) == "1.2s · ctx 420 / 8,192")
    }

    @Test func summaryIsNilWithNoFields() {
        let a = EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil)
        #expect(a.summary == nil)
    }

    @Test func terminalShowsOutcome() {
        var t = EngineTranscript()
        t.apply(.turnEnded(outcome: "tool-limit"))
        #expect(t.rows.last == .error("Turn ended: tool-limit"))
        t.apply(.turnEnded(outcome: "answered"))
        #expect(t.rows.last == .system("Turn ended: answered"))
    }
}

struct EngineToolCardFormattingTests {
    private func card(op: String, path: String? = nil, ok: Bool? = nil, durationMs: Double? = nil) -> EngineToolCard {
        EngineToolCard(tool: EngineTool(op: op, path: path), ok: ok, durationMs: durationMs)
    }

    private func resumed(_ turns: [EngineResumed.Turn], rewoundTo: Int? = nil) -> EngineResumed {
        EngineResumed(sessionID: "s1", turns: turns, rewoundTo: rewoundTo, filesChanged: 0, contextUsed: nil)
    }

    @Test func dividerTextPerKind() {
        let r = resumed([], rewoundTo: 2)
        #expect(r.divider(after: EngineRelaunch(kind: .rewind, argv: [], reason: "")) == "Rewound to prompt 2")
        #expect(r.divider(after: EngineRelaunch(kind: .model, argv: ["--model-id", "m"], reason: ""))
            == "Switched to m: new conversation, files kept")
        #expect(r.divider(after: EngineRelaunch(kind: .resume, argv: [], reason: "")) == "Resumed session s1")
        #expect(r.divider(after: nil) == "Resumed session s1")
    }

    @Test func resumedReplacesRows() {
        var t = EngineTranscript()
        t.appendUser("a"); t.apply(.notice("n")); t.apply(.narration("x")); t.appendSystem("y"); t.appendUser("/rewind 1")
        t.apply(.resumed(resumed([.init(prompt: "p", answer: "q", stopped: false)], rewoundTo: 1)))
        #expect(t.rows.count == 3)
        #expect(t.rows.first == .divider("Resumed session s1"))
        #expect(t.rows[1] == .user("p"))
        guard case .answer(let a) = t.rows[2] else { Issue.record("no answer row"); return }
        #expect(a.text == "q")
        #expect(t.pendingUserCount == 0)
    }

    @Test func resumedWithNoTurnsShowsDividerOnly() {
        var t = EngineTranscript()
        t.appendUser("hi")
        t.apply(.resumed(resumed([])))
        #expect(t.rows == [.divider("Resumed session s1")])
    }

    @Test func stoppedTurnShowsStopped() {
        var t = EngineTranscript()
        t.apply(.resumed(resumed([.init(prompt: "p", answer: nil, stopped: true)])))
        #expect(Array(t.rows.dropFirst()) == [.user("p"), .system("Stopped.")])
    }

    /// Final review: a declined card never takes another call's end or result.
    @Test func declinedCardDoesNotTakeAnotherCallsEnd() {
        var t = EngineTranscript()
        let tool = EngineTool(op: "read", path: "a.swift")
        t.apply(.toolStart(tool))
        t.apply(.toolRejected(EngineToolRejection(name: "read", reason: "repeated-call", path: "a.swift", text: "x")))
        t.apply(.toolEnd(tool, ok: true, durationMs: 5))
        let cards = t.rows.compactMap { if case .tool(let c) = $0 { c } else { nil } }
        #expect(cards.first?.ok == true)
        #expect(cards.last?.ok == nil && cards.last?.rejection != nil)
    }

    @Test func declinedCardText() {
        var t = EngineTranscript()
        t.apply(.toolRejected(EngineToolRejection(
            name: "read", reason: "repeated-call", path: nil, text: "repeated call")))
        guard case .tool(let c)? = t.rows.last else { Issue.record("no card"); return }
        #expect(c.headerText == "read")
        #expect(c.metadataLine == "declined · repeated")
        #expect(c.icon == "xmark.circle")
    }

    @Test func declinedCardWithoutName() {
        var t = EngineTranscript()
        t.apply(.toolRejected(EngineToolRejection(name: "", reason: "malformed", path: nil, text: "bad call")))
        guard case .tool(let c)? = t.rows.last else { Issue.record("no card"); return }
        #expect(c.headerText == "a call")
        #expect(c.metadataLine == "declined · malformed")
    }

    @Test func headerTextIncludesPathWhenPresent() {
        #expect(card(op: "read", path: "a.swift").headerText == "read a.swift")
    }

    @Test func headerTextIsOpAloneWithNoPath() {
        #expect(card(op: "bash", path: nil).headerText == "bash")
        #expect(card(op: "bash", path: "").headerText == "bash")
    }

    @Test func answerSummaryUsesDuration() {
        let a = EngineAnswer(text: "x", contextUsed: nil, contextSize: nil, durationMs: 75_000)
        #expect(a.summary(locale: Locale(identifier: "en_US")) == "75s")
    }

    @Test func metadataLineRunningHasNoDuration() {
        #expect(card(op: "read").metadataLine == "running")
    }

    @Test func metadataLineSucceededUnderTenSecondsUsesOneDecimal() {
        #expect(card(op: "read", ok: true, durationMs: 1234).metadataLine == "succeeded · 1.2s")
    }

    @Test func metadataLineFailedAtOrOverTenSecondsUsesNoDecimal() {
        #expect(card(op: "read", ok: false, durationMs: 12_000).metadataLine == "failed · 12s")
    }

    @Test func metadataLineIgnoresNegativeOrNonFiniteDuration() {
        #expect(card(op: "read", ok: true, durationMs: -1).metadataLine == "succeeded")
        #expect(card(op: "read", ok: true, durationMs: .nan).metadataLine == "succeeded")
    }

    @Test func iconMatchesEachKnownOp() {
        #expect(card(op: "bash").icon == "terminal")
        #expect(card(op: "bash_status").icon == "terminal")
        #expect(card(op: "bash_stop").icon == "terminal")
        #expect(card(op: "write").icon == "doc.badge.plus")
        #expect(card(op: "edit").icon == "square.and.pencil")
        #expect(card(op: "ls").icon == "folder")
        #expect(card(op: "read").icon == "doc.text.magnifyingglass")
        #expect(card(op: "more").icon == "doc.text.magnifyingglass")
        #expect(card(op: "grep").icon == "magnifyingglass")
        #expect(card(op: "unknown-op").icon == "wrench.and.screwdriver")
    }

    // MARK: SU.5a2 Task 2: Quick Look resolves against the source

    @Test func fileURLResolvesAgainstSource() {
        let c = EngineToolCard(tool: EngineTool(op: "read", path: "Sources/a.swift"))
        #expect(c.fileURL(source: URL(fileURLWithPath: "/r"))?.path == "/r/Sources/a.swift")
        #expect(c.fileURL(source: URL(fileURLWithPath: "/r/"))?.path == "/r/Sources/a.swift")
    }

    @Test func fileURLKeepsAbsolutePaths() {
        let c = EngineToolCard(tool: EngineTool(op: "read", path: "/etc/hosts"))
        #expect(c.fileURL(source: URL(fileURLWithPath: "/r"))?.path == "/etc/hosts")
    }

    @Test func fileURLNilWithoutPathOrSource() {
        #expect(EngineToolCard(tool: EngineTool(op: "bash", path: nil)).fileURL(source: URL(fileURLWithPath: "/r")) == nil)
        #expect(EngineToolCard(tool: EngineTool(op: "read", path: "a")).fileURL(source: nil) == nil)
    }
}
