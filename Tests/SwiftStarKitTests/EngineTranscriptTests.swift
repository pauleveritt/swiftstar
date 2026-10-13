import Testing
import Foundation
@testable import SwiftStarKit

// Dropped in SU.5b: stopDisabledWhileQueued (a strict subset of
// stopDisabledWhenAwaitingInput) and busyStartsOnPromptEvent (covered by
// the pending table's `.prompt` row and stopDisabledWhenAwaitingInput).

struct EngineTranscriptTests {
    private func cards(_ t: EngineTranscript) -> [EngineToolCard] {
        t.rows.compactMap { if case .tool(let c) = $0 { c } else { nil } }
    }

    private func resumed(_ turns: [EngineResumed.Turn], rewoundTo: Int? = nil) -> EngineResumed {
        EngineResumed(sessionID: "s1", turns: turns, rewoundTo: rewoundTo, filesChanged: 0, contextUsed: nil)
    }

    @Test func toolReadFixtureBuildsRows() throws {
        var t = EngineTranscript()
        t.appendUser("go")
        for e in try Fixtures.events("tool-read.ndjson") { t.apply(e) }
        let cs = cards(t)
        #expect(cs.count == 1)
        #expect(cs.allSatisfy { $0.ok == true && $0.result != nil })
        #expect(t.rows.filter { if case .answer = $0 { true } else { false } }.count == 1)
        // SU.6a: the 27B's narration is the reply; nothing is left as a narration row.
        #expect(!t.rows.contains { if case .narration = $0 { true } else { false } })
        let reply = t.rows.compactMap { if case .answer(_, let r) = $0 { r } else { nil } }.first
        #expect(reply?.hasPrefix("`Package.swift` declares") == true)
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

    @Test func commandRowIsNotLeftPending() {
        var t = EngineTranscript()
        t.appendUser("/help")
        t.apply(.notice("commands: ..."))
        t.apply(.awaitingInput)
        #expect(t.pendingUserCount == 0)
        #expect(!t.isPending(rowAt: 0))
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

    @Test func promptClearsSeveralPending() {
        var t = EngineTranscript()
        t.appendUser("a")
        t.appendUser("b")
        #expect(t.pendingUserCount == 2)
        t.apply(.prompt("a\n\nb"))
        #expect(t.pendingUserCount == 0)
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

    @Test func terminalShowsOutcome() {
        var t = EngineTranscript()
        t.apply(.turnEnded(outcome: "tool-limit"))
        #expect(t.rows.last == .error("Turn ended: tool-limit"))
        t.apply(.turnEnded(outcome: "answered"))
        #expect(t.rows.last == .system("Turn ended: answered"))
    }

    @Test func resumedReplacesRows() {
        var t = EngineTranscript()
        t.appendUser("a"); t.apply(.notice("n")); t.apply(.narration("x")); t.appendSystem("y"); t.appendUser("/rewind 1")
        t.apply(.resumed(resumed([.init(prompt: "p", answer: "q", stopped: false)], rewoundTo: 1)))
        #expect(t.rows.count == 3)
        #expect(t.rows.first == .divider("Resumed session s1"))
        #expect(t.rows[1] == .user("p"))
        guard case .answer(let a, _) = t.rows[2] else { Issue.record("no answer row"); return }
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

    // MARK: which events clear the pending (not yet started) user rows

    struct PendingCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let event: EngineEvent
        let clears: Bool
    }

    static let pendingCases: [PendingCase] = [
        .init(testDescription: "pendingClearsOnError", event: .error("queue full"), clears: true),
        .init(testDescription: "closedAndRefusedClearPending (closed)", event: .closed(capturePath: nil), clears: true),
        .init(testDescription: "closedAndRefusedClearPending (refused)", event: .refused("no"), clears: true),
        .init(testDescription: "awaitingInput clears", event: .awaitingInput, clears: true),
        .init(testDescription: "prompt clears", event: .prompt("x"), clears: true),
        .init(testDescription: "steering clears", event: .steering(applied: true), clears: true),
        .init(testDescription: "relaunch clears",
              event: .relaunch(EngineRelaunch(kind: .rewind, argv: ["tui"], reason: "")), clears: true),
        .init(testDescription: "pendingSurvivesLoadingAndGenerating (loading)", event: .loading("mapping"), clears: false),
        .init(testDescription: "pendingSurvivesLoadingAndGenerating (generating)", event: .generating(true), clears: false),
        .init(testDescription: "pauseAndMemoryLeavePending (pause)",
              event: .pause(PauseMetrics(prefillTokens: 1, prefillMs: 1, evalCount: 1, evalMs: 1)), clears: false),
        .init(testDescription: "pauseAndMemoryLeavePending (memory)",
              event: .memory(EngineMemory(allocatedBytes: 1, budgetBytes: 2, planGiB: nil)), clears: false),
    ]

    @Test(arguments: pendingCases) func pending(_ c: PendingCase) {
        var t = EngineTranscript()
        t.appendUser("x")
        t.apply(c.event)
        #expect(t.isPending(rowAt: 0) == !c.clears)
    }

    // MARK: answers

    struct AnswerCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let answer: EngineAnswer
        let row: TranscriptRow
    }

    static let answerCases: [AnswerCase] = [
        .init(testDescription: "emptyAnswerShowsReason",
              answer: EngineAnswer(text: "", contextUsed: 1, contextSize: 2, durationMs: nil, reason: "ran out of tokens"),
              row: .error("No answer: ran out of tokens")),
        .init(testDescription: "emptyAnswerWithoutReasonHasFallback",
              answer: EngineAnswer(text: "", contextUsed: nil, contextSize: nil, durationMs: nil),
              row: .error("No answer — the model stopped without answering")),
        .init(testDescription: "nonEmptyAnswerStaysAnAnswer",
              answer: EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil),
              row: .answer(EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil))),
    ]

    @Test(arguments: answerCases) func answerRow(_ c: AnswerCase) {
        var t = EngineTranscript()
        t.apply(.answer(c.answer))
        #expect(t.rows.last == c.row)
    }

    // MARK: a narration absorbs its turn's answer (SU.6a)

    private static func ans(_ text: String) -> EngineAnswer {
        EngineAnswer(text: text, contextUsed: nil, contextSize: nil, durationMs: nil)
    }

    private static let readTool = EngineTool(op: "read", path: "a.swift")
    private static let readCard = EngineToolCard(tool: readTool, ok: true, durationMs: 5)

    struct AbsorbCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        /// Applied after `appendUser("go")`.
        let events: [EngineEvent]
        /// The rows after `.user("go")`.
        let rows: [TranscriptRow]
    }

    static let absorbCases: [AbsorbCase] = [
        .init(testDescription: "narrationBecomesTheAnswerBody",
              events: [.narration("full reply"), .answer(ans("short"))],
              rows: [.answer(ans("short"), reply: "full reply")]),
        .init(testDescription: "equalTextsShowOnce",
              events: [.narration("same\n"), .answer(ans(" same"))],
              rows: [.answer(ans(" same"), reply: nil)]),
        .init(testDescription: "toolBetweenBlocksTheMerge",
              events: [.narration("plan"), .toolStart(readTool), .toolEnd(readTool, ok: true, durationMs: 5),
                       .answer(ans("done"))],
              rows: [.narration("plan"), .tool(readCard), .answer(ans("done"), reply: nil)]),
        .init(testDescription: "onlyTheLastNarrationMerges",
              events: [.narration("plan"), .toolStart(readTool), .toolEnd(readTool, ok: true, durationMs: 5),
                       .narration("reply"), .answer(ans("done"))],
              rows: [.narration("plan"), .tool(readCard), .answer(ans("done"), reply: "reply")]),
        .init(testDescription: "stoppedTurnKeepsNarration",
              events: [.narration("partial"), .interrupted(contextUsed: nil, contextSize: nil)],
              rows: [.narration("partial"), .system("Stopped.")]),
        .init(testDescription: "emptyAnswerKeepsNarration",
              events: [.narration("partial"), .answer(ans(""))],
              rows: [.narration("partial"), .error("No answer — the model stopped without answering")]),
    ]

    @Test(arguments: absorbCases) func absorb(_ c: AbsorbCase) {
        var t = EngineTranscript()
        t.appendUser("go")
        for e in c.events { t.apply(e) }
        #expect(t.rows == [.user("go")] + c.rows)
    }

    @Test func promptBetweenNarrationAndAnswerStaysPending() {
        var t = EngineTranscript()
        t.appendUser("go")
        t.apply(.prompt("go"))
        t.apply(.narration("full reply"))
        t.appendUser("more")
        t.apply(.answer(Self.ans("short")))
        #expect(t.rows == [.user("go"), .answer(Self.ans("short"), reply: "full reply"), .user("more")])
        #expect(t.isPending(rowAt: 2))
    }

    struct SummaryCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let answer: EngineAnswer
        let summary: String?
    }

    static let summaryCases: [SummaryCase] = [
        .init(testDescription: "summaryJoinsDurationAndContext",
              answer: EngineAnswer(text: "hi", contextUsed: 420, contextSize: 8192, durationMs: 1234),
              summary: "1.2s · ctx 420 / 8,192"),
        .init(testDescription: "summaryIsNilWithNoFields",
              answer: EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil), summary: nil),
        .init(testDescription: "answerSummaryUsesDuration",
              answer: EngineAnswer(text: "x", contextUsed: nil, contextSize: nil, durationMs: 75_000), summary: "75s"),
    ]

    @Test(arguments: summaryCases) func answerSummary(_ c: SummaryCase) {
        #expect(c.answer.summary(locale: Locale(identifier: "en_US")) == c.summary)
    }

    // MARK: tool card text

    struct CardCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let card: EngineToolCard
        let header: String
        let metadata: String
        let icon: String
    }

    private static func card(_ op: String, _ path: String? = nil, ok: Bool? = nil, ms: Double? = nil) -> EngineToolCard {
        EngineToolCard(tool: EngineTool(op: op, path: path), ok: ok, durationMs: ms)
    }

    /// The card a `tool_rejected` event appends, through the transcript.
    private static func declined(_ name: String, _ reason: String) -> EngineToolCard {
        var t = EngineTranscript()
        t.apply(.toolRejected(EngineToolRejection(name: name, reason: reason, path: nil, text: "x")))
        guard case .tool(let c)? = t.rows.last else { return card("<no card appended>") }
        return c
    }

    static let cardCases: [CardCase] = [
        .init(testDescription: "headerTextIncludesPathWhenPresent (metadataLineRunningHasNoDuration)",
              card: card("read", "a.swift"), header: "read a.swift", metadata: "running", icon: "doc.text.magnifyingglass"),
        .init(testDescription: "headerTextIsOpAloneWithNoPath (nil)", card: card("bash"),
              header: "bash", metadata: "running", icon: "terminal"),
        .init(testDescription: "headerTextIsOpAloneWithNoPath (empty)", card: card("bash", ""),
              header: "bash", metadata: "running", icon: "terminal"),
        .init(testDescription: "metadataLineSucceededUnderTenSecondsUsesOneDecimal", card: card("read", ok: true, ms: 1234),
              header: "read", metadata: "succeeded · 1.2s", icon: "doc.text.magnifyingglass"),
        .init(testDescription: "metadataLineFailedAtOrOverTenSecondsUsesNoDecimal", card: card("read", ok: false, ms: 12_000),
              header: "read", metadata: "failed · 12s", icon: "doc.text.magnifyingglass"),
        .init(testDescription: "metadataLineIgnoresNegativeOrNonFiniteDuration (negative)", card: card("read", ok: true, ms: -1),
              header: "read", metadata: "succeeded", icon: "doc.text.magnifyingglass"),
        .init(testDescription: "metadataLineIgnoresNegativeOrNonFiniteDuration (nan)", card: card("read", ok: true, ms: .nan),
              header: "read", metadata: "succeeded", icon: "doc.text.magnifyingglass"),
        .init(testDescription: "iconMatchesEachKnownOp (bash_status)", card: card("bash_status"),
              header: "bash_status", metadata: "running", icon: "terminal"),
        .init(testDescription: "iconMatchesEachKnownOp (bash_stop)", card: card("bash_stop"),
              header: "bash_stop", metadata: "running", icon: "terminal"),
        .init(testDescription: "iconMatchesEachKnownOp (write)", card: card("write"),
              header: "write", metadata: "running", icon: "doc.badge.plus"),
        .init(testDescription: "iconMatchesEachKnownOp (edit)", card: card("edit"),
              header: "edit", metadata: "running", icon: "square.and.pencil"),
        .init(testDescription: "iconMatchesEachKnownOp (ls)", card: card("ls"),
              header: "ls", metadata: "running", icon: "folder"),
        .init(testDescription: "iconMatchesEachKnownOp (more)", card: card("more"),
              header: "more", metadata: "running", icon: "doc.text.magnifyingglass"),
        .init(testDescription: "iconMatchesEachKnownOp (grep)", card: card("grep"),
              header: "grep", metadata: "running", icon: "magnifyingglass"),
        .init(testDescription: "iconMatchesEachKnownOp (unknown)", card: card("unknown-op"),
              header: "unknown-op", metadata: "running", icon: "wrench.and.screwdriver"),
        .init(testDescription: "declinedCardText", card: declined("read", "repeated-call"),
              header: "read", metadata: "declined · repeated", icon: "xmark.circle"),
        .init(testDescription: "declinedCardWithoutName", card: declined("", "malformed"),
              header: "a call", metadata: "declined · malformed", icon: "xmark.circle"),
    ]

    @Test(arguments: cardCases) func cardText(_ c: CardCase) {
        #expect(c.card.headerText == c.header)
        #expect(c.card.metadataLine == c.metadata)
        #expect(c.card.icon == c.icon)
    }

    // MARK: Quick Look file URLs

    struct FileURLCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let path: String?
        let source: String?
        let expected: String?
    }

    static let fileURLCases: [FileURLCase] = [
        .init(testDescription: "fileURLResolvesAgainstSource", path: "Sources/a.swift", source: "/r",
              expected: "/r/Sources/a.swift"),
        .init(testDescription: "fileURLResolvesAgainstSource (trailing slash)", path: "Sources/a.swift", source: "/r/",
              expected: "/r/Sources/a.swift"),
        .init(testDescription: "fileURLKeepsAbsolutePaths", path: "/etc/hosts", source: "/r", expected: "/etc/hosts"),
        .init(testDescription: "fileURLNilWithoutPathOrSource (no path)", path: nil, source: "/r", expected: nil),
        .init(testDescription: "fileURLNilWithoutPathOrSource (no source)", path: "a", source: nil, expected: nil),
    ]

    @Test(arguments: fileURLCases) func fileURL(_ c: FileURLCase) {
        let card = EngineToolCard(tool: EngineTool(op: "read", path: c.path))
        #expect(card.fileURL(source: c.source.map { URL(fileURLWithPath: $0) })?.path == c.expected)
    }

    // MARK: the divider over a rebuilt transcript

    struct DividerCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let relaunch: EngineRelaunch?
        let text: String
    }

    static let dividerCases: [DividerCase] = [
        .init(testDescription: "dividerTextPerKind (rewind)",
              relaunch: EngineRelaunch(kind: .rewind, argv: [], reason: ""), text: "Rewound to prompt 2"),
        .init(testDescription: "dividerTextPerKind (model)",
              relaunch: EngineRelaunch(kind: .model, argv: ["--model-id", "m"], reason: ""),
              text: "Switched to m: new conversation, files kept"),
        .init(testDescription: "dividerTextPerKind (resume)",
              relaunch: EngineRelaunch(kind: .resume, argv: [], reason: ""), text: "Resumed session s1"),
        .init(testDescription: "dividerTextPerKind (none)", relaunch: nil, text: "Resumed session s1"),
    ]

    @Test(arguments: dividerCases) func divider(_ c: DividerCase) {
        let r = EngineResumed(sessionID: "s1", turns: [], rewoundTo: 2, filesChanged: 0, contextUsed: nil)
        #expect(r.divider(after: c.relaunch) == c.text)
    }
}
