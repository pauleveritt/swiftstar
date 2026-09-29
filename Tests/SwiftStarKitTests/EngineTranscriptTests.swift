import Testing
import Foundation
@testable import SwiftStarKit

struct EngineTranscriptTests {
    static func events(fromFixture name: String) throws -> [EngineEvent] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/engine")
        let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        var parser = EngineWireParser()
        return text.split(whereSeparator: \.isNewline).map { parser.parse(String($0)) }
    }

    private func cards(_ t: EngineTranscript) -> [EngineToolCard] {
        t.rows.compactMap { if case .tool(let c) = $0 { c } else { nil } }
    }

    @Test func toolReadFixtureBuildsRows() throws {
        var t = EngineTranscript()
        t.appendUser("go")
        for e in try Self.events(fromFixture: "tool-read.ndjson") { t.apply(e) }
        let cs = cards(t)
        #expect(cs.count == 2)
        #expect(cs.allSatisfy { $0.ok == true && $0.result != nil })
        #expect(t.rows.filter { if case .answer = $0 { true } else { false } }.count == 1)
        #expect(!t.isBusy && !t.isGenerating && !t.isAwaitingInput)
    }

    @Test func transcriptKeepsSessionInfo() throws {
        var t = EngineTranscript()
        #expect(t.session == nil)
        var sawSession = false
        for e in try Self.events(fromFixture: "tool-read.ndjson") {
            t.apply(e)
            if case .session = e {
                sawSession = true
                #expect(t.session?.modelID == "laguna-xs-2.1")
                #expect(t.session?.contextSize == 20000)
            }
        }
        #expect(sawSession)
        t.apply(.closed(capturePath: nil))
        #expect(t.session == nil)
    }

    @Test func repeatedReadsGetOwnResults() {
        let tool = EngineTool(op: "read", path: "a")
        let res = EngineToolResult(tool: tool, resultKind: "k", preview: "p", truncated: false)
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
        for e in try Self.events(fromFixture: "tool-read.ndjson") {
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
        #expect(!t.canStop)
        t.appendUser("hi")
        #expect(!t.canStop)
        t.apply(.prompt("hi"))
        #expect(t.canStop)
    }

    @Test func interruptedAddsStoppedRow() throws {
        var t = EngineTranscript()
        t.appendUser("go")
        for e in try Self.events(fromFixture: "stop.ndjson") { t.apply(e) }
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
        #expect(!t.canStop)
    }

    @Test func busyStartsOnPromptEvent() {
        var t = EngineTranscript()
        t.appendUser("x")
        t.apply(.prompt("x"))
        #expect(t.canStop)
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
        #expect(t.canStop)
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
        t.apply(.pause(PauseMetrics(prefillTokens: 1, prefillMs: 1, evalCount: 1, evalMs: 1, outputTokens: 1)))
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
        t.apply(.steering(applied: true, text: "a\n\nb"))
        #expect(t.pendingUserCount == 0)
        #expect(t.queuedUserRows.isEmpty)
        #expect(t.rows.last == .system("Queued message delivered"))
        t.apply(.steering(applied: false, text: nil))
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

    @Test func terminalShowsOutcome() {
        var t = EngineTranscript()
        t.apply(.turnEnded(outcome: "tool-limit"))
        #expect(t.rows.last == .error("Turn ended: tool-limit"))
        t.apply(.turnEnded(outcome: "answered"))
        #expect(t.rows.last == .system("Turn ended: answered"))
    }
}
