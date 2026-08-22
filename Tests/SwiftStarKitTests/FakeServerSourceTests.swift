import Testing
import Foundation
@testable import SwiftStarKit

struct FakeServerSourceTests {
    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/server")
    }
    private func load(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesRoot.appendingPathComponent(name))
    }

    @Test func generationIsDeterministic() throws {
        let capture = try load("golden.short.sse")
        let sidecar = try load("golden.short.sse.sidecar")
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/e"),
            modelPath: URL(fileURLWithPath: "/tmp/m.gguf"), port: 12345
        )
        let a = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: ServerCommand.argv(settings: settings))
        let b = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: ServerCommand.argv(settings: settings))
        #expect(a == b)
    }

    @Test func generatedSourceEmbedsExpectedArgv() throws {
        let capture = try load("golden.short.sse")
        let sidecar = try load("golden.short.sse.sidecar")
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/e"),
            modelPath: URL(fileURLWithPath: "/tmp/m.gguf"), port: 12345
        )
        let source = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: ServerCommand.argv(settings: settings))
        #expect(source.contains(#""-m""#))
        #expect(source.contains(#""/tmp/m.gguf""#))
        #expect(source.contains(#""--port""#))
    }

    @Test func generatedSourceEmbedsEveryCaptureLine() throws {
        let capture = try load("golden.short.sse")
        let sidecar = try load("golden.short.sse.sidecar")
        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ["/tmp/e/ds4-server", "-m", "/tmp/m.gguf", "-c", "32768", "--host", "127.0.0.1", "--port", "12345"]
        )
        let lines = String(decoding: capture, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for line in lines {
            // The generator embeds each line as an escaped Swift literal.
            #expect(source.contains(FakeServerSource.swiftStringLiteral(String(line))),
                    "generated source must embed every capture line")
        }
    }

    @Test func refusesMalformedCapture() {
        let capture = Data("data: {\"a\":1}\nthis line is not sse\n".utf8)
        let sidecar = Data("1000\n2000\n".utf8)
        #expect(throws: FakeServerError.self) {
            _ = try FakeServerSource.generate(
                capture: capture, sidecar: sidecar,
                engineArgv: ["/tmp/e/ds4-server"]
            )
        }
    }

    @Test func refusesLineCountMismatch() {
        let capture = Data("data: {\"a\":1}\n".utf8)
        let sidecar = Data("1000\n2000\n".utf8)
        #expect(throws: FakeServerError.self) {
            _ = try FakeServerSource.generate(
                capture: capture, sidecar: sidecar,
                engineArgv: ["/tmp/e/ds4-server"]
            )
        }
    }

    @Test func refusalSiblingSucceeds() throws {
        // Sibling to refusesMalformedCapture: a clean capture generates.
        let capture = Data("data: {\"a\":1}\ndata: [DONE]\n".utf8)
        let sidecar = Data("1000\n3000\n".utf8)
        let source = try FakeServerSource.generate(
            capture: capture, sidecar: sidecar,
            engineArgv: ["/tmp/e/ds4-server"]
        )
        #expect(source.contains(FakeServerSource.swiftStringLiteral("data: {\"a\":1}")))
        #expect(source.contains(FakeServerSource.swiftStringLiteral("data: [DONE]")))
    }

    @Test func escaperHandlesQuotesAndBackslashes() {
        // Direct escaper test: the generated literal for a payload containing
        // quotes and backslashes must round-trip. End-to-end byte fidelity is
        // pinned by the integration-tier event-equivalence test (Task 7).
        #expect(FakeServerSource.swiftStringLiteral("a \"b\" \\ c") == #""a \"b\" \\ c""#)
        #expect(FakeServerSource.swiftStringLiteral("line1\nline2") == #""line1\nline2""#)
    }
}
