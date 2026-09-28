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

    @Test func stopDisabledWhenAwaitingInput() {
        var t = EngineTranscript()
        t.apply(.awaitingInput)
        #expect(!t.canStop)
        t.appendUser("hi")
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
