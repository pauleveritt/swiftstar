import Testing
import Foundation
@testable import SwiftStarKit

struct EngineWireParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/engine")
    }

    private static func events(fromFixture name: String) throws -> [EngineEvent] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(name), encoding: .utf8)
        var parser = EngineWireParser()
        return text.split(whereSeparator: \.isNewline).map { parser.parse(String($0)) }
    }

    private static func ready() -> EngineWireParser {
        var p = EngineWireParser()
        _ = p.parse(#"{"kind":"ready","protocol":1}"#)
        return p
    }

    private static func event(_ body: String) -> String {
        #"{"kind":"event","event":{"# + body + "}}"
    }

    @Test func firstLineMustBeReady() {
        var p = EngineWireParser()
        guard case .protocolError(let m) = p.parse(#"{"kind":"input"}"#) else {
            Issue.record("expected protocolError"); return
        }
        #expect(m.contains("input"))
    }

    @Test func protocolTwoIsRefused() {
        var p = EngineWireParser()
        guard case .protocolError(let m) = p.parse(#"{"kind":"ready","protocol":2}"#) else {
            Issue.record("expected protocolError"); return
        }
        #expect(m.contains("protocol 2"))
    }

    @Test func nonJSONIsProtocolError() {
        var p = Self.ready()
        guard case .protocolError = p.parse("garbage") else {
            Issue.record("expected protocolError"); return
        }
    }

    @Test func unknownEventKindIsIgnored() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"flux_capacitor""#)) == .ignored)
    }

    @Test func toolReadFixtureDecodes() throws {
        let events = try Self.events(fromFixture: "tool-read.ndjson")
        let results = events.compactMap { e -> EngineToolResult? in
            if case .toolResult(let r) = e { return r } else { return nil }
        }
        #expect(results.count == 2)
        for r in results {
            #expect(r.tool.op == "read")
            #expect(r.tool.path == "Package.swift")
            #expect(!r.preview.isEmpty)
        }
        let answers = events.compactMap { e -> EngineAnswer? in
            if case .answer(let a) = e { return a } else { return nil }
        }
        #expect(answers.count == 1)
        #expect((answers.first?.contextUsed ?? 0) > 0)
        let pauses = events.compactMap { e -> PauseMetrics? in
            if case .pause(let m) = e { return m } else { return nil }
        }
        #expect(!pauses.isEmpty)
        #expect(pauses.allSatisfy { $0.evalCount > 0 })
        guard case .closed = events.last(where: { $0 != .ignored }) else {
            Issue.record("last non-ignored event is not closed"); return
        }
    }

    @Test func stopFixtureHasInterrupted() throws {
        #expect(try Self.events(fromFixture: "stop.ndjson").contains(.interrupted))
    }

    @Test func errorFixtureHasError() throws {
        let events = try Self.events(fromFixture: "error.ndjson")
        #expect(events.contains { if case .error(let m) = $0 { m.contains("bogus") } else { false } })
    }

    @Test func unavailableSnapshotIsIgnored() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"checkpoint","snapshot":{"status":"unavailable"}"#)) == .ignored)
    }

    @Test func nullSnapshotFieldsAreNil() {
        var p = Self.ready()
        let e = p.parse(Self.event(#""kind":"checkpoint","snapshot":{"eval_count":8,"sync_ms":null}"#))
        guard case .pause(let m) = e else { Issue.record("expected pause"); return }
        #expect(m.evalCount == 8)
        #expect(m.prefillMs == nil)
        #expect(m.prefillTokens == nil)
    }

    @Test func missingOptionalFieldsAreNil() {
        var p = Self.ready()
        let e = p.parse(Self.event(#""kind":"answer","text":"hi""#))
        #expect(e == .answer(EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil)))
    }

    @Test func refusalBecomesRefused() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"apply_refused","reason":"no changes""#)) == .refused("no changes"))
    }

    @Test func helpBecomesNotice() {
        var p = Self.ready()
        let e = p.parse(Self.event(#""kind":"help","lines":["/help","/status"]"#))
        guard case .notice(let t) = e else { Issue.record("expected notice"); return }
        #expect(!t.isEmpty)
        #expect(t.contains("/status"))
    }

    @Test func noticeWithoutTextFallsBackToKind() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"clear""#)) == .notice("clear"))
    }

    @Test func nativeEventsAreGenerating() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"native_start""#)) == .generating(true))
        #expect(p.parse(Self.event(#""kind":"native_end""#)) == .generating(false))
    }
}
