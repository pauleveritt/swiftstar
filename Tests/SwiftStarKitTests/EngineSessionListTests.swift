import Foundation
import Testing
@testable import SwiftStarKit

// SU.7a: `ds4-dogfood sessions --json`, grouped into conversations.
struct EngineSessionListTests {
    private static func fixture() throws -> [EngineSessionEntry] {
        try EngineSessionEntry.decodeList(Data(contentsOf: Fixtures.root.appendingPathComponent("sessions.json"))).get()
    }

    private static func date(_ s: String) -> Date? { EngineSessionEntry.parseUpdated(s) }

    private static func entry(_ id: String, from: String? = nil, first: String? = nil, updated: String? = nil,
                              model: String? = nil, resumable: Bool? = true) -> EngineSessionEntry {
        EngineSessionEntry(id: id, path: "/s/\(id)", modelID: model, updated: updated.flatMap(date),
                           firstPrompt: first, resumedFrom: from.map { "/s/\($0)" }, resumable: resumable)
    }

    @Test func decodesTheCapture() throws {
        let entries = try Self.fixture()
        #expect(entries.count == 12)
        #expect(entries.first?.id.wholeMatch(of: /\d{8}-\d{6}-.+/) != nil)
        #expect(entries.first?.updated != nil)
    }

    @Test func groupsTheCapture() throws {
        let rows = Conversations.group(try Self.fixture())
        #expect(rows.count == 7)
        let three = try #require(rows.first { $0.id == "20261013-123136-swiftstar" })
        #expect(three.sessionIDs == ["20261013-123136-swiftstar", "20261013-122439-swiftstar", "20261013-122106-swiftstar"])
        #expect(three.title == "Hello")
    }

    struct DecodeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let json: String
        /// nil when decoding should fail as malformed.
        let check: Check?
        enum Check: Sendable { case resumedFromNil, updatedNil, decodes }
    }

    static let decodeCases: [DecodeCase] = [
        .init(testDescription: "unknownKeysIgnored", json: #"[{"id":"a","path":"/p","zzz":1}]"#, check: .decodes),
        .init(testDescription: "resumedFromNull", json: #"[{"id":"a","path":"/p","resumed_from":null}]"#,
              check: .resumedFromNil),
        .init(testDescription: "garbageUpdatedIsNil", json: #"[{"id":"a","path":"/p","updated":"garbage"}]"#,
              check: .updatedNil),
        .init(testDescription: "garbageIsMalformed", json: "nope", check: nil),
    ]

    @Test(arguments: decodeCases) func decodeEdges(_ c: DecodeCase) {
        let result = EngineSessionEntry.decodeList(Data(c.json.utf8))
        switch (result, c.check) {
        case (.success(let e), .resumedFromNil?): #expect(e.first?.resumedFrom == nil)
        case (.success(let e), .updatedNil?): #expect(e.first?.updated == nil)
        case (.success(let e), .decodes?): #expect(e.map(\.id) == ["a"])
        case (.failure(.malformed), nil): break
        default: Issue.record("unexpected \(result)")
        }
    }

    struct GroupCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let entries: [EngineSessionEntry]
        /// (id, title) per row, in order.
        let rows: [String]
    }

    static let groupCases: [GroupCase] = [
        .init(testDescription: "alone", entries: [entry("a", first: "Hi", updated: "2026-10-13T10:00:00")],
              rows: ["a: Hi"]),
        .init(testDescription: "chainOfThree", entries: [
            entry("c", from: "b", first: "later", updated: "2026-10-13T12:00:00"),
            entry("b", from: "a", first: "middle", updated: "2026-10-13T11:00:00"),
            entry("a", first: "first", updated: "2026-10-13T10:00:00"),
        ], rows: ["c: first"]),
        .init(testDescription: "rootNotListed", entries: [
            entry("c", from: "b", first: "later", updated: "2026-10-13T12:00:00"),
            entry("b", from: "gone", first: "middle", updated: "2026-10-13T11:00:00"),
        ], rows: ["c: middle"]),
        .init(testDescription: "branch", entries: [
            entry("c", from: "a", first: "two", updated: "2026-10-13T12:00:00"),
            entry("b", from: "a", first: "one", updated: "2026-10-13T11:00:00"),
            entry("a", first: "root", updated: "2026-10-13T10:00:00"),
        ], rows: ["c: root", "b: root"]),
        .init(testDescription: "untitled (missing or empty first prompt)", entries: [
            entry("b", first: "", updated: "2026-10-13T11:00:00"), entry("a", updated: "2026-10-13T10:00:00"),
        ], rows: ["b: Untitled", "a: Untitled"]),
        .init(testDescription: "newestFirst (nil updated last)", entries: [
            entry("x", first: "no date"), entry("a", first: "old", updated: "2026-10-13T10:00:00"),
            entry("b", first: "new", updated: "2026-10-13T12:00:00"),
        ], rows: ["b: new", "a: old", "x: no date"]),
        .init(testDescription: "cycle (the walk stops)", entries: [
            entry("c", from: "b", first: "C", updated: "2026-10-13T12:00:00"),
            entry("b", from: "a", first: "B", updated: "2026-10-13T11:00:00"),
            entry("a", from: "b", first: "A", updated: "2026-10-13T10:00:00"),
        ], rows: ["c: A"]),
    ]

    @Test(arguments: groupCases) func group(_ c: GroupCase) {
        #expect(Conversations.group(c.entries).map { "\($0.id): \($0.title)" } == c.rows)
    }

    @Test(arguments: [
        (String?.some("qwen3.8-27b"), true, "12m ago · qwen3.8-27b"),
        (nil, true, "12m ago"),
        ("qwen3.8-27b", false, "qwen3.8-27b"),
    ]) func subtitle(_ model: String?, _ dated: Bool, _ expected: String) throws {
        let now = try #require(Self.date("2026-10-13T12:12:00"))
        let c = Conversations.group([Self.entry("a", first: "x", updated: dated ? "2026-10-13T12:00:00" : nil, model: model)])
        #expect(Conversations.subtitle(try #require(c.first), now: now, locale: Locale(identifier: "en_US")) == expected)
    }

    @Test(arguments: [
        ("/x/sessions/20261013-112927-swiftstar/run-7-1.partial.json", String?.some("20261013-112927-swiftstar")),
        ("x", nil),
    ]) func directoryID(_ path: String, _ id: String?) {
        #expect(EngineSessionEntry.directoryID(fromCapturePath: path) == id)
    }
}
