import Testing
import Foundation
@testable import SwiftStarKit

struct SSEParserTests {
    // Repo root derived from this file's path: Tests/SwiftStarKitTests/SSEParserTests.swift
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/server")
    }

    /// Parsed once (static lazy init); tests share it instead of re-reading.
    static let shortEvents: [SSEEvent] = {
        let text = try! String(contentsOf: fixturesRoot.appendingPathComponent("golden.short.sse"), encoding: .utf8)
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            if let event = parser.feed(String(line)) { events.append(event) }
        }
        return events
    }()

    private func parseFixture(_ name: String) throws -> [SSEEvent] {
        let text = try String(contentsOf: Self.fixturesRoot.appendingPathComponent(name), encoding: .utf8)
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            if let event = parser.feed(String(line)) { events.append(event) }
        }
        return events
    }

    @Test func firstChunkIsRoleAssistant() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.first == .roleAssistant)
    }

    @Test func reasoningAndContentDeltasBothPresent() throws {
        let events = Self.shortEvents
        #expect(events.contains { if case .reasoning = $0 { return true } else { return false } })
        #expect(events.contains { if case .content = $0 { return true } else { return false } })
    }

    @Test func endsWithDoneAfterFinish() throws {
        let events = Self.shortEvents
        #expect(events.last == .done)
        #expect(events.dropLast().last == .finish(.stop))
    }

    @Test func goldenSseParsesWithoutRefusing() throws {
        // The P1 wire has no version handshake (binding rule 7, P5 adds one):
        // parsing must produce events, never refuse. Real invariants, not a count.
        let events = try parseFixture("golden.sse")
        #expect(events.first == .roleAssistant)
        #expect(events.last == .done)
    }

    @Test func unknownFieldIsIgnoredNotRefused() {
        var parser = SSEParser()
        let line = #"data: {"id":"x","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"future_field":"z"},"finish_reason":null}]}"#
        let event = parser.feed(line)
        if case .ignored(let payload) = event {
            #expect(payload.contains("future_field"))
        } else {
            Issue.record("expected .ignored, got \(String(describing: event))")
        }
    }

    @Test func nonDataLinesAreSkipped() {
        var parser = SSEParser()
        #expect(parser.feed("") == nil)
        #expect(parser.feed(": a comment") == nil)
        #expect(parser.feed("event: message") == nil)
    }

    @Test func doneLineParses() {
        var parser = SSEParser()
        #expect(parser.feed("data: [DONE]") == .done)
    }

    @Test func malformedDataIsIgnoredNotRefused() {
        var parser = SSEParser()
        if case .ignored(let payload) = parser.feed("data: not json at all") {
            #expect(payload == "not json at all")
        } else {
            Issue.record("expected .ignored")
        }
    }

    @Test func reasoningTakesPrecedenceOverContentInSameDelta() {
        // A delta carrying both fields must not silently drop reasoning.
        var parser = SSEParser()
        let line = #"data: {"choices":[{"index":0,"delta":{"reasoning_content":"r","content":"c"},"finish_reason":null}]}"#
        #expect(parser.feed(line) == .reasoning("r"))
    }

    @Test func emptyDeltasAreNotEmitted() {
        // Some servers send content:"" on the role chunk; that must not become
        // an empty .content event downstream.
        var parser = SSEParser()
        let line = #"data: {"choices":[{"index":0,"delta":{"content":""},"finish_reason":null}]}"#
        let event = parser.feed(line)
        if case .ignored = event {} else {
            Issue.record("expected .ignored for empty delta, got \(String(describing: event))")
        }
    }

    @Test func contentAndFinishInOneChunkKeepsContent() {
        // Terminal chunks may carry both content and finish_reason; content wins
        // (finish is deferred to the following [DONE]).
        var parser = SSEParser()
        let line = #"data: {"choices":[{"index":0,"delta":{"content":"last"},"finish_reason":"stop"}]}"#
        #expect(parser.feed(line) == .content("last"))
    }
}
