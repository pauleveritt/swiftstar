import Testing
import Foundation
@testable import SwiftStarKit

struct SSEParserTests {
    // Repo root derived from this file's path: Tests/SwiftStarKitTests/SSEParserTests.swift
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/server")
    }

    private func parseFixture(_ name: String) throws -> [SSEEvent] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(name), encoding: .utf8)
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let event = parser.feed(String(line)) { events.append(event) }
        }
        return events
    }

    @Test func firstChunkIsRoleAssistant() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.first == .roleAssistant)
    }

    @Test func reasoningAndContentDeltasBothPresent() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.contains { if case .reasoning = $0 { return true } else { return false } })
        #expect(events.contains { if case .content = $0 { return true } else { return false } })
    }

    @Test func endsWithDoneAfterFinish() throws {
        let events = try parseFixture("golden.short.sse")
        #expect(events.last == .done)
        #expect(events.dropLast().last == .finish(.stop))
    }

    @Test func unknownFieldIsIgnoredNotRefused() {
        var parser = SSEParser()
        let line = #"data: {"id":"x","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"future_field":"z"},"finish_reason":null}]}"#
        let event = parser.feed(line)
        #expect(event == .ignored( #"{"id":"x","object":"chat.completion.chunk","created":1,"model":"m","choices":[{"index":0,"delta":{"future_field":"z"},"finish_reason":null}]}"# ))
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
        #expect(parser.feed("data: not json at all") == .ignored("not json at all"))
    }

    @Test func noHandshakeRequired() throws {
        // The P1 wire has no version handshake (binding rule 7, P5 adds one).
        // Parsing the fixture must not refuse: it must produce events, not throw.
        let events = try parseFixture("golden.sse")
        #expect(events.count > 10)
    }
}
