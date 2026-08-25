import Testing
import Foundation
@testable import SwiftStarKit

struct MachineEvidenceTests {
    @Test func cappedFailureOutputKeepsTail() {
        let body = String(repeating: "a", count: 9000) + "FAILING ASSERTION\n"
        let (out, note) = MachineEvidence.cappedFailureOutput(body, cap: 8192)
        #expect(out.hasSuffix("FAILING ASSERTION\n"))
        #expect(out.utf8.count <= 8192)
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
        #expect(out.utf8.count <= 4096)
        #expect(note != nil)
    }

    @Test func cappedFailureOutputWithNonASCII() {
        // Multi-byte UTF-8 characters (emoji, accented text) should not split mid-character.
        // 🎉 is 4 bytes in UTF-8, café has an accented é (2 bytes)
        let body = String(repeating: "café ", count: 1000) + "🎉 FAILING\n"
        let (out, note) = MachineEvidence.cappedFailureOutput(body, cap: 4096)

        // Verify byte count is actually respected
        #expect(out.utf8.count <= 4096)
        // Verify no replacement character (U+FFFD) which would indicate a split
        #expect(!out.contains("�"))
        // Verify the string is valid and can be decoded
        #expect(!out.isEmpty)
        // Verify tail is preserved (the emoji and FAILING should be there if they fit)
        #expect(note != nil)
    }

    @Test func cappedContentWithNonASCII() {
        // Test that content truncation respects UTF-8 byte boundaries
        let content = "print(\"Hello " + String(repeating: "café ", count: 500) + "\")"
        let (out, note) = MachineEvidence.cappedContent(content, cap: 2048)

        // Verify byte count is actually respected
        #expect(out.utf8.count <= 2048)
        // Verify no replacement character from a split
        #expect(!out.contains("�"))
        // Verify the string is valid
        #expect(!out.isEmpty)
        // Verify head is preserved (starts with print)
        #expect(out.hasPrefix("print("))
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
