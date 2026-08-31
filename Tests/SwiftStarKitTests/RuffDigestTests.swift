import Testing
import Foundation
@testable import SwiftStarKit

struct RuffDigestTests {
    private static let sample = """
    [{"code":"F401","message":"`os` imported but unused","filename":"src/app.py","location":{"row":12,"column":1}},
     {"code":"F401","message":"`sys` imported but unused","filename":"src/app.py","location":{"row":13,"column":1}},
     {"code":"E501","message":"line too long (92 > 88)","filename":"src/util.py","location":{"row":88,"column":1}}]
    """

    @Test func groupsByRuleAndFile() {
        let out = CommandOutput(stdout: Self.sample, stderr: "", exit: 1, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-a.log")
        #expect(d.summary.contains("ruff: 3 diagnostics, 2 files (exit 1)"))
        #expect(d.summary.contains("[1] F401 — 2 in 1 file"))
        #expect(d.summary.contains("[2] E501 — 1 in 1 file"))
        #expect(d.summary.contains("src/app.py:12:1 `os` imported but unused"))
        #expect(d.summary.contains("Ran: uv run ruff check --output-format=json"))
    }

    @Test func zeroDiagnosticsIsExplicit() {
        let out = CommandOutput(stdout: "[]", stderr: "", exit: 0, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-b.log")
        #expect(d.summary.contains("0 diagnostics"))
        #expect(d.summary.contains("all clean"))
    }

    @Test func unparseableFallsBackToBoundedSummary() {
        let out = CommandOutput(stdout: "error: unrecognized option", stderr: "", exit: 2, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-c.log")
        #expect(d.summary.contains("ruff: could not parse"))
        #expect(d.summary.contains("full output: /runs/lint-c.log"))
    }

    @Test func condenseIsANoopForManyDiagnostics() {
        var items: [String] = []
        for i in 0..<150 {
            items.append("{\"code\":\"E501\",\"message\":\"line too long\",\"filename\":\"src/f\(i).py\",\"location\":{\"row\":1,\"column\":1}}")
        }
        let out = CommandOutput(stdout: "[" + items.joined(separator: ",") + "]", stderr: "", exit: 1, timedOut: false)
        let d = RuffDigest.digest(out, command: "uv run ruff check --output-format=json", artifactPath: "/runs/lint-d.log")
        #expect(ToolResultCondenser.condense(d.summary) == d.summary)
    }
}
