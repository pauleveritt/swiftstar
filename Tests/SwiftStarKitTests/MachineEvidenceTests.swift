import Testing
import Foundation
@testable import SwiftStarKit

struct MachineEvidenceTests {
    @Test func cappedFailureOutputKeepsTail() {
        let body = String(repeating: "a", count: 9000) + "FAILING ASSERTION\n"
        let (out, note) = MachineEvidence.cappedFailureOutput(body, cap: 8192)
        #expect(out.hasSuffix("FAILING ASSERTION\n"))
        #expect(out.count <= 8192)
        #expect(out.hasPrefix("a"))
        #expect(note != nil)
    }

    @Test func cappedFailureOutputUnderCapIsUnchanged() {
        let (out, note) = MachineEvidence.cappedFailureOutput("short\n", cap: 8192)
        #expect(out == "short\n")
        #expect(note == nil)
    }

    @Test func cappedContentTruncatesAndNotes() {
        let (out, note) = MachineEvidence.cappedContent(String(repeating: "x", count: 5000), cap: 4096)
        #expect(out.count <= 4096)
        #expect(note != nil)
    }

    @Test func redactHitsFindsOnlyRedactedStrings() {
        let e = MachineEvidence(failureOutput: "assert 307 == 303", fileContents: ["app.py": "return RedirectResponse(\"/complaints\")"], truncations: [])
        #expect(e.redactHits(["303"]) == ["303"])
        #expect(e.redactHits(["default_factory"]).isEmpty)
    }

    @Test func renderContainsHeaderAndFiles() {
        let e = MachineEvidence(failureOutput: "FAIL", fileContents: ["app.py": "code"], truncations: [])
        let r = e.render()
        #expect(r.contains("Failure evidence (machine output)"))
        #expect(r.contains("=== app.py ==="))
        #expect(r.contains("code"))
    }
}
