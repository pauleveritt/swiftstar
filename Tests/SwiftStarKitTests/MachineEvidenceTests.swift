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
        // Middle-truncation: the kept string is no longer bounded by `cap` alone
        // (it also carries an inline marker), but the real content contributed
        // by head+tail must still be bounded by roughly `cap`.
        let (out, note) = MachineEvidence.cappedContent(String(repeating: "x", count: 5000), cap: 4096)
        #expect(out.utf8.count > 4096)   // marker text pushes it past the raw cap
        #expect(out.utf8.count < 5000)   // but real content is still reduced
        #expect(note != nil)
    }

    @Test func cappedContentMiddleTruncationKeepsHeadAndTailDropsMiddle() throws {
        // Distinct head/tail markers with a large distinguishable middle blob,
        // so we can assert the middle is genuinely gone (not just bounded) and
        // that both ends survive. Head and tail are each sized past half the
        // cap so the kept windows land entirely within them, never bleeding
        // into the middle blob's text.
        let head = "HEAD_START_" + String(repeating: "a", count: 1200)
        let middle = String(repeating: "MIDDLE_BLOB_", count: 2000)
        let tail = String(repeating: "b", count: 1200) + "_TAIL_END"
        let content = head + middle + tail
        let (out, note) = MachineEvidence.cappedContent(content, cap: 2048)

        #expect(out.hasPrefix("HEAD_START_"))
        #expect(out.hasSuffix("_TAIL_END"))
        #expect(!out.contains("MIDDLE_BLOB_"))
        #expect(out.contains("truncated"))   // inline marker present in the content itself
        #expect(out.utf8.count < content.utf8.count)

        let unwrappedNote = try #require(note)
        #expect(unwrappedNote.contains("middle truncated"))
        #expect(unwrappedNote.contains("\(content.utf8.count)"))
    }

    @Test func cappedContentUnderCapIsUnchanged() {
        let (out, note) = MachineEvidence.cappedContent("short\n", cap: 4096)
        #expect(out == "short\n")
        #expect(note == nil)
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

        // Verify byte count is bounded (the inline middle-truncation marker adds
        // some overhead on top of the raw cap, but the kept real content is
        // still roughly cap-sized and well short of the original).
        #expect(out.utf8.count <= 2048 + 256)
        #expect(out.utf8.count < content.utf8.count)
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
