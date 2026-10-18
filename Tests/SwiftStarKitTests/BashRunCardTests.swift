import Foundation
import Testing
@testable import SwiftStarKit

/// SU.18, D2: a `run` that fell back to bash under `--allow-bash` arrives as
/// `op: "run"` with no path; its exit and time are the result's first line
/// (ds4-engine `run_tool.py:119-124` at `a84b79bd`), and `result_kind` is
/// "ok" whatever the exit, so the card reads the header itself.
struct BashRunCardTests {
    private static func card(_ preview: String?, ok: Bool? = true, path: String? = "") -> EngineToolCard {
        let tool = EngineTool(op: "run", path: path)
        return EngineToolCard(
            tool: tool, ok: preview == nil ? nil : ok, durationMs: 2400,
            result: preview.map { EngineToolResult(tool: tool, preview: $0, truncated: false) })
    }

    @Test func exitZero() {
        let c = Self.card("[exit 0 in 2.3 s]\n5 passed")
        #expect(c.bashRun == BashRun(exit: 0, seconds: "2.3", timedOut: false))
        #expect(c.headerText == "bash")
        #expect(c.icon == "terminal")
        #expect(c.metadataLine == "ran as bash in the sandbox · exit 0 · 2.3 s")
        #expect(!c.failed)
    }

    @Test func exitOneIsAFailure() {
        let c = Self.card("[exit 1 in 0.4 s]\nerror: no such module")
        #expect(c.metadataLine == "ran as bash in the sandbox · exit 1 · 0.4 s")
        #expect(c.failed)
    }

    @Test func stoppedAtTheLimit() {
        let c = Self.card("[stopped after 120 s, the time limit]\npartial output")
        #expect(c.bashRun == BashRun(exit: nil, seconds: nil, timedOut: true))
        #expect(c.metadataLine == "ran as bash in the sandbox · stopped at the 120 s limit")
        #expect(c.failed)
    }

    @Test func stillRunning() {
        let c = Self.card(nil)
        #expect(c.headerText == "bash")
        #expect(c.metadataLine == "ran as bash in the sandbox · running")
        #expect(!c.failed)
    }

    @Test func otherCardsAreUnchanged() {
        // A `run` with a path is not the bash fallback's shape.
        let withPath = Self.card("[exit 0 in 1.0 s]", path: "script.sh")
        #expect(withPath.bashRun == nil)
        #expect(withPath.headerText == "run script.sh")
        let read = EngineToolCard(tool: EngineTool(op: "read", path: "a.py"), ok: false, durationMs: 10)
        #expect(read.failed)
        #expect(!EngineToolCard(tool: EngineTool(op: "read", path: "a.py"), ok: true, durationMs: 10).failed)
    }
}

/// SU.18, D5: the live recording, `fixtures/engine/bash-run.ndjson` (the 27B
/// at ds4-engine `a84b79bd`, `--allow-bash`).
struct BashRunRecordingTests {
    @Test func theRecordingMakesAReadCardAndABashCard() throws {
        var t = EngineTranscript()
        try Fixtures.events("bash-run.ndjson").forEach { t.apply($0) }
        let cards = t.rows.compactMap { row -> EngineToolCard? in if case .tool(let c) = row { c } else { nil } }
        // `cat Package.swift`, mapped by the engine: on the wire, a plain read.
        #expect(cards.first?.headerText == "read Package.swift")
        #expect(cards.first?.isBashRun == false)
        // `ls Sources | wc -l`, a pipe: run as bash.
        let bash = try #require(cards.last)
        #expect(bash.headerText == "bash")
        #expect(bash.metadataLine == "ran as bash in the sandbox · exit 0 · 0.0 s")
        #expect(!bash.failed)
    }
}
