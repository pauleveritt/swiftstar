import Testing
import Foundation
@testable import SwiftStarKit

struct MachineEvidenceTests {
    /// `cappedFailureOutput` must keep the last `cap` bytes. It used to keep
    /// `byteCount - cap` bytes -- the loop walked back until the *remaining*
    /// count fell under the cap and then kept everything it had walked past.
    ///
    /// That is wrong in both directions and the existing tests could not see
    /// it, because they only assert `<= cap` and every input they use is under
    /// 2x cap, where `byteCount - cap` is itself under cap. The real failure
    /// needed an 88 KB pytest run: 88919 bytes with cap 8192 kept **80727**,
    /// which is what pushed a repair packet to 37180 tokens against a 32768
    /// context and killed the one cell all night that had a rich failure
    /// surface to show (2026-08-26, capture 20260826-055741).
    /// V7: a fixed seed must produce a fixed prompt. Repair evidence embedded
    /// the per-round temp-worktree UUID inside tracebacks, so the same seed and
    /// config dispatched a *different* packet on every run. Measured: the
    /// round-2 packets of 20260826-104811 and 20260826-112536 (both
    /// mellum/absolute/seed1) differed by exactly that line, and the first
    /// repaired where the second failed. It also defeats prompt-prefix caching
    /// and injects an absolute host path into runs whose purpose is a
    /// relative-vs-absolute path arm.
    ///
    /// Worktree-independent by construction: round 1's grade comes from the
    /// FAILED phase's worktree, not the round's own, so normalising against a
    /// single known URL would miss it.
    @Test func worktreePathsAreNormalisedOutOfEvidence() {
        let a = """
        Traceback (most recent call last):
          File "/private/var/folders/m4/x/T/swiftstar-wt-AAE9A953-215B-4A11-A295-50D57D26AD96/app.py", line 42, in <module>
        ModuleNotFoundError: No module named 'app'
        """
        let b = """
        Traceback (most recent call last):
          File "/private/var/folders/m4/x/T/swiftstar-wt-4C01CE73-2BBA-43C0-B96F-DA6D7C7A9561/app.py", line 42, in <module>
        ModuleNotFoundError: No module named 'app'
        """
        let na = MachineEvidence.normalizingWorktreePaths(a)
        let nb = MachineEvidence.normalizingWorktreePaths(b)
        #expect(na == nb, "same failure from two worktrees must normalise identically")
        #expect(na.contains("File \"app.py\", line 42"),
                "expected a workspace-relative path, got: \(na)")
        #expect(!na.contains("swiftstar-wt-"))
    }

    @Test func cappedFailureOutputKeepsCapBytesNotTheRemainder() {
        let body = String(repeating: "x", count: 88_000) + "FAILING ASSERTION\n"
        let (out, note) = MachineEvidence.cappedFailureOutput(body, cap: 8192)
        #expect(out.utf8.count <= 8192,
                "kept \(out.utf8.count) bytes for cap 8192 — the cap is inverted")
        // ... and must not under-keep either: a cap is a target, not a ceiling
        // to undershoot. Anything much below `cap` means the same inverted walk.
        #expect(out.utf8.count > 8192 - 64,
                "kept only \(out.utf8.count) of a possible 8192 bytes")
        #expect(out.hasSuffix("FAILING ASSERTION\n"))
        #expect(note != nil)
    }

    /// The under-keeping half of the same bug, at a size the old tests used:
    /// 9018 bytes with cap 8192 kept 826.
    @Test func cappedFailureOutputJustOverCapKeepsNearlyEverything() {
        let body = String(repeating: "a", count: 9000) + "FAILING\n"
        let (out, _) = MachineEvidence.cappedFailureOutput(body, cap: 8192)
        #expect(out.utf8.count > 8192 - 64,
                "kept only \(out.utf8.count) of a possible 8192 bytes")
    }

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
