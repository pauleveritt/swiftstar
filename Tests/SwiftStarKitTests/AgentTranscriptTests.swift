import Testing
import Foundation
@testable import SwiftStarKit

struct AgentTranscriptTests {
    private static let hello = AgentEvent.hello(version: 1, capabilities: ["text", "tool", "status", "ts"])

    @Test func contentCoalesces() {
        var t = AgentTranscript()
        t.apply(.text("Hello "))
        t.apply(.text("world"))
        #expect(t.rows == [.content("Hello world")])
    }

    @Test func thinkingCoalescesSeparately() {
        var t = AgentTranscript()
        t.apply(.think("hmm"))
        t.apply(.think(" more"))
        t.apply(.text("answer"))
        #expect(t.rows == [.thinking("hmm more"), .content("answer")])
    }

    @Test func leadingNewlineQuirkStripsOnce() {
        // json-events.md quirk: the first text after a `think` starts with
        // leading newlines (one or two from the renderer, more possible from
        // the model). Strip all leading whitespace on exactly that chunk.
        var t = AgentTranscript()
        t.apply(.think("done"))
        t.apply(.text("\n\n\nThe answer"))
        t.apply(.text(" and more"))  // a later chunk is not stripped
        #expect(t.rows == [.thinking("done"), .content("The answer and more")])
    }

    @Test func singleCallBlockBuildsCard() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramValue, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "seed.txt", status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "read", params: [ToolParam(name: "path", value: "seed.txt")], output: nil, status: nil))])
    }

    @Test func emptyParamValueStillAddsParam() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "write", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        // An empty-string parameter value emits no param_value event (json-events.md).
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "content", paramName: "content", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "write", params: [ToolParam(name: "path", value: ""), ToolParam(name: "content", value: "")], output: nil, status: nil))])
    }

    @Test func outputAttributedToSameBlockAfterFinish() {
        // json-events.md ordering guarantee: a block's output events land
        // after its finish but before the next block's start.
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "bash", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        t.apply(.tool(AgentToolEvent(phase: .output, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "hello-world\n", status: nil, calls: nil)))
        #expect(t.rows == [.tool(ToolCard(name: "bash", params: [], output: "hello-world\n", status: nil))])
    }

    @Test func interruptedFinishSetsStatusOnCard() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: "[tool call interrupted]\n", calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "read", params: [], output: nil, status: "[tool call interrupted]\n"))])
    }

    @Test func multiCallBlockKeysCardsByIdx() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "list", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 1, name: "bash", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 1, name: nil, paramKind: "bash_command", paramName: "command", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramValue, idx: 1, name: nil, paramKind: nil, paramName: nil, value: "pwd", status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 1, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 1, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 2)))
        #expect(t.rows == [
            .tool(ToolCard(name: "list", params: [], output: nil, status: nil)),
            .tool(ToolCard(name: "bash", params: [ToolParam(name: "command", value: "pwd")], output: nil, status: nil)),
        ])
    }

    @Test func blockStartClearsPriorBlockCards() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        // A new block restarts idx at 0: the card map is cleared at `start`, so
        // the new block's idx-0 card is a fresh row, never the old block's card.
        // (A stale `output` arriving after the new `start` is a wire violation
        // — json-events.md guarantees a block's outputs land before the next
        // start — and the reducer does not defend against it: once the new
        // block's `tool` phase re-keys idx 0, a late output attaches to that
        // card. That case is undefined per D4; this test pins the defined one.)
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "edit", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        #expect(t.rows.count == 2)
        #expect(t.rows[0] == .tool(ToolCard(name: "read", params: [], output: nil, status: nil)))
        #expect(t.rows[1] == .tool(ToolCard(name: "edit", params: [], output: nil, status: nil)))
    }

    @Test func zeroCallFinishIsIgnored() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 0)))
        #expect(t.rows.isEmpty)
    }

    @Test func systemRowAppends() {
        var t = AgentTranscript()
        t.appendSystem("> hello")
        #expect(t.rows == [.system("> hello")])
    }

    @Test func goldenToolsTranscriptBuildsToolCards() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent/golden-tools.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var t = AgentTranscript()
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if let e = parser.feed(s) { t.apply(e) }
        }
        let cards = t.rows.compactMap { if case .tool(let card) = $0 { return card } else { return nil } }
        #expect(!cards.isEmpty)
        #expect(cards.contains { $0.name == "bash" && $0.output != nil })  // the echo output surfaced on its card
        #expect(cards.contains { $0.name == "read" })
        #expect(cards.contains { $0.name == "write" || $0.name == "edit" })
    }
}
