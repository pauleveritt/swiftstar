import Testing
import Foundation
@testable import SwiftStarKit

struct AgentTranscriptTests {
    private static let hello = AgentEvent.hello(version: 1, capabilities: ["text", "tool", "status", "ts"])

    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent")
    }

    /// Replays a committed wire fixture through a fresh parser/transcript and
    /// returns the resulting tool cards. Shared by the `golden-tools*` tests
    /// below so the fixture-path construction and feed loop live in one place.
    private func toolCards(fromFixture name: String) throws -> [ToolCard] {
        let url = Self.fixturesRoot.appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var t = AgentTranscript()
        for line in text.split(whereSeparator: \.isNewline) {
            if let e = parser.feed(String(line)) { t.apply(e) }
        }
        return t.rows.compactMap { if case .tool(let card) = $0 { return card } else { return nil } }
    }

    @Test func contentCoalesces() {
        var t = AgentTranscript()
        t.apply(.text("Hello "))
        t.apply(.text("world"))
        #expect(t.rows == [.content("Hello world", summary: nil)])
    }

    @Test func thinkingCoalescesSeparately() {
        var t = AgentTranscript()
        t.apply(.think("hmm"))
        t.apply(.think(" more"))
        t.apply(.text("answer"))
        #expect(t.rows == [.thinking("hmm more"), .content("answer", summary: nil)])
    }

    @Test func leadingNewlineQuirkStripsOnce() {
        // json-events.md quirk: the first text after a `think` starts with
        // leading newlines (one or two from the renderer, more possible from
        // the model). Strip all leading whitespace on exactly that chunk.
        var t = AgentTranscript()
        t.apply(.think("done"))
        t.apply(.text("\n\n\nThe answer"))
        t.apply(.text(" and more"))  // a later chunk is not stripped
        #expect(t.rows == [.thinking("done"), .content("The answer and more", summary: nil)])
    }

    @Test func singleCallBlockBuildsCard() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramValue, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "seed.txt", status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "read", params: [ToolParam(name: "path", value: "seed.txt", kind: "path")], output: nil, status: nil, path: "seed.txt", finished: true))])
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
        #expect(t.rows == [.tool(ToolCard(name: "write", params: [ToolParam(name: "path", value: "", kind: "path"), ToolParam(name: "content", value: "", kind: "content")], output: nil, status: nil, path: "", finished: true))])
    }

    @Test func outputAttributedToSameBlockAfterFinish() {
        // json-events.md ordering guarantee: a block's output events land
        // after its finish but before the next block's start.
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "bash", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        t.apply(.tool(AgentToolEvent(phase: .output, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "hello-world\n", status: nil, calls: nil)))
        #expect(t.rows == [.tool(ToolCard(name: "bash", params: [], output: "hello-world\n", status: nil, finished: true))])
    }

    @Test func interruptedFinishSetsStatusOnCard() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: "[tool call interrupted]\n", calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "read", params: [], output: nil, status: "[tool call interrupted]\n", finished: true))])
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
            .tool(ToolCard(name: "bash", params: [ToolParam(name: "command", value: "pwd", kind: "bash_command")], output: nil, status: nil, finished: true)),
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
        #expect(t.rows[0] == .tool(ToolCard(name: "read", params: [], output: nil, status: nil, finished: true)))
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

    @Test func consultedRowAppends() {
        var t = AgentTranscript()
        t.append(.consulted(WorkerId(1), "the worker's answer"))
        #expect(t.rows == [.consulted(WorkerId(1), "the worker's answer")])
    }

    @Test func reducerIsAppendOnly() {
        // The transcript ForEach is keyed by offset (AgentView). That is only
        // correct while the reducer appends and mutates in place — never
        // inserts before an existing row or removes one. This pins the
        // invariant: a later event stream leaves every earlier row a prefix.
        var t = AgentTranscript()
        t.apply(.text("hello"))
        t.apply(.think("thinking"))
        t.appendUser("a prompt")
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        let snapshot = t.rows
        t.apply(.text(" more prose"))
        t.appendSystem("> a system note")
        t.append(.consulted(WorkerId(1), "delegated result"))
        #expect(Array(t.rows.prefix(snapshot.count)) == snapshot)
    }

    @Test func goldenToolsTranscriptBuildsToolCards() throws {
        let cards = try toolCards(fromFixture: "golden-tools.ndjson")
        #expect(!cards.isEmpty)
        #expect(cards.contains { $0.name == "bash" && $0.output != nil })  // the echo output surfaced on its card
        #expect(cards.contains { $0.name == "read" })
        #expect(cards.contains { $0.name == "write" || $0.name == "edit" })
    }

    @Test func goldenToolsKindsAreParsed() throws {
        // The P21 "golden recapture" premise was wrong: the fixture already
        // carries the `kind` fields across all five kinds — the gap was
        // assertions, not a clean recapture run.
        let cards = try toolCards(fromFixture: "golden-tools.ndjson")
        let params = cards.flatMap(\.params)
        #expect(params.contains { $0.kind == "path" })
        #expect(cards.contains { $0.path != nil })
        #expect(params.contains { $0.kind == "content" })
        #expect(params.contains { $0.kind == "bash_command" })
        #expect(params.contains { $0.kind == "diff_old" })
        #expect(params.contains { $0.kind == "diff_new" })
    }

    @Test func goldenToolsXsTranscriptBuildsToolCards() throws {
        let cards = try toolCards(fromFixture: "golden-tools-xs.ndjson")
        #expect(!cards.isEmpty)
        #expect(cards.contains { $0.name == "bash" && $0.output != nil })  // the echo output surfaced on its card
        #expect(cards.contains { $0.name == "read" })
        #expect(cards.contains { $0.name == "write" })
        #expect(cards.contains { $0.name == "edit" })
        #expect(cards.contains { $0.name == "list" })
    }

    @Test func goldenToolsXsKindsAndFinishedAreParsed() throws {
        // Closes the ROADMAP backlog item "the golden agent capture predates
        // the wire's kind field": golden-tools.ndjson was captured before
        // param_begin's kind field, so its kind/path/finished enrichment had
        // no committed-fixture proof. golden-tools-xs.ndjson postdates that —
        // it carries kind on every param_begin (path, content, bash_command,
        // diff_old, diff_new: the full five-kind zoo) — and this is also the
        // first fixture test to assert `finished`, which neither of the
        // golden-tools tests above ever checked.
        let cards = try toolCards(fromFixture: "golden-tools-xs.ndjson")
        let params = cards.flatMap(\.params)
        #expect(params.contains { $0.kind == "path" })
        #expect(params.contains { $0.kind == "content" })
        #expect(params.contains { $0.kind == "bash_command" })
        #expect(params.contains { $0.kind == "diff_old" })
        #expect(params.contains { $0.kind == "diff_new" })
        #expect(cards.contains { $0.path == "seed.txt" })
        // Every one of the capture's 8 tool blocks reaches a `finish` phase —
        // this fixture never has an in-flight or interrupted card.
        #expect(cards.count == 8)
        #expect(cards.allSatisfy { $0.finished })
    }
}
