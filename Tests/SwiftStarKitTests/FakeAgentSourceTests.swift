import Testing
import Foundation
@testable import SwiftStarKit

struct FakeAgentSourceTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    private func load(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixturesRoot.appendingPathComponent(name))
    }

    private func makeArgv() -> [String] {
        ["-m", "/tmp/model.gguf", "-c", "32768", "--metal", "--non-interactive",
         "--json-events", "--workspace", "/tmp/ws", "--shell", "off"]
    }

    @Test func generatesFromRealToolCapture() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        // The fake embeds the expected argv (including the consent flags) and
        // the replay lines from the real capture. Capture lines are embedded as
        // escaped Swift string literals (FakeServerSource.swiftStringLiteral
        // escapes `"` -> `\"`), so a `"phase":"start"` fragment appears in the
        // source in its escaped form `\"phase\":\"start\"`.
        #expect(source.contains("\"-m\", \"/tmp/model.gguf\""))
        #expect(source.contains("\"--workspace\", \"/tmp/ws\""))
        #expect(source.contains("\"--shell\", \"off\""))
        #expect(source.contains(#"\"phase\":\"start\""#))
        #expect(source.contains("argv mismatch"))
    }

    @Test func rejectsInvalidUTF8() {
        let bad = Data([0xFF, 0xFE, 0x00, 0x01])  // torn/invalid UTF-8
        #expect(throws: FakeAgentError.invalidUTF8) {
            _ = try FakeAgentSource.generate(capture: bad, engineArgv: makeArgv())
        }
    }

    @Test func determinism() throws {
        let a = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        let b = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        #expect(a == b)
    }

    @Test func delaysDeriveFromTsDeltas() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        // The first replay line (hello) carries delay 0; every line's delay is
        // derived from consecutive ts deltas (fork divergence #7), so the fake
        // needs no sidecar file.
        #expect(source.contains("(0, "))
    }

    // MARK: - host-tools mode (P9)

    @Test func hostToolsDeterminism() throws {
        let a = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: true)
        let b = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: true)
        #expect(a == b)
    }

    @Test func hostToolsOffMatchesObservationByteForByte() throws {
        // The default (hostTools: false) must be byte-for-byte the existing
        // observation-only replay — no behavior change when the mode is off.
        let obs = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        let off = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: false)
        #expect(obs == off)
    }

    @Test func hostToolsEmitsToolRequest() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: true)
        // The host-tools replay replaces the `tool` phase stream with
        // `tool_request` events (one per call), embedded as escaped Swift
        // string literals (swiftStringLiteral escapes `"` -> `\"`).
        #expect(source.contains(#"\"t\":\"tool_request\""#))
    }

    @Test func hostToolsSkipsToolPhaseStream() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: true)
        // The tool phase events (start/param_*/finish/output) are collected into
        // tool_request lines and are NOT emitted as capture lines; the replay
        // carries only non-tool lines (status/text/ready/hello) + the requests.
        #expect(!source.contains(#"\"phase\":\"start\""#))
        #expect(!source.contains(#"\"phase\":\"finish\""#))
        #expect(!source.contains(#"\"phase\":\"output\""#))
    }

    @Test func hostToolsRequestCarriesNameAndParams() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: true)
        // The first tool block is `write` with params path=seed.txt,
        // content="hello from golden-tools". The request JSON carries the
        // tool name and the param values.
        #expect(source.contains(#"\"name\":\"write\""#))
        #expect(source.contains(#"\"value\":\"seed.txt\""#))
        #expect(source.contains(#"\"value\":\"hello from golden-tools\""#))
    }

    @Test func hostToolsStillEmitsNonToolLines() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv(), hostTools: true)
        // status/text/ready/hello are non-tool lines and pass through unchanged.
        #expect(source.contains(#"\"t\":\"status\""#))
        #expect(source.contains(#"\"t\":\"ready\""#))
        #expect(source.contains(#"\"t\":\"hello\""#))
    }
}
