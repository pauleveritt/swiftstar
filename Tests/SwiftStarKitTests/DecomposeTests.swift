import Testing
import Foundation
@testable import SwiftStarKit

/// P12.5 (D2): `decompose(_:)` moved from `swiftstar-agenttest/main.swift` into
/// `SwiftStarKit` so it is unit-testable, plus the offset-0 fix — a model's
/// decompose reply is the one shape (opens directly with `## Phase 1: …`, no
/// title line first) the original host-only splitter got wrong.
struct DecomposeTests {
    /// Reads a real host spec fixture the same way `HarvestCaptureReplayTests`
    /// locates `fixtures/agenttest/harvest/*.txt` — relative to this test
    /// file, so it works regardless of the working directory `swift test` runs
    /// from.
    private func fixtureSpec(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agenttest/specs/\(name).md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - the offset-0 regression this design exists to fix

    /// The single most likely model reply shape: no title line, no leading
    /// newline, straight into the first heading. Before the fix this parsed
    /// to 0 phases (the splitter never matches at position 0); after, 1.
    @Test func offsetZeroSinglePhaseHeadingYieldsOnePhaseNotZero() {
        let reply = "## Phase 1: Home page\n\nCreate app.py with the FastAPI app instance."

        let (preamble, phases) = decompose(reply)

        #expect(phases.count == 1)
        #expect(preamble.isEmpty)
        #expect(phases[0].hasPrefix("## Phase 1: Home page"))
        #expect(phases[0].contains("Create app.py"))
    }

    /// Multi-phase offset-0: before the fix, phase 1's boundary (invisible to
    /// the splitter at position 0) was lost into `preamble` while phase 2's
    /// boundary (which *does* have a preceding "\n") was found — so this
    /// reply parsed to 1 phase (phase 2 only), silently dropping phase 1's
    /// task text. After the fix, both phases are recovered.
    @Test func offsetZeroMultiPhaseYieldsAllPhasesNoneDroppedIntoPreamble() {
        let reply = """
        ## Phase 1: Home page

        Create app.py with the FastAPI app instance.

        ## Phase 2: Complaints board

        Add the /complaints route.
        """

        let (preamble, phases) = decompose(reply)

        #expect(preamble.isEmpty)
        #expect(phases.count == 2)
        #expect(phases[0].contains("Phase 1: Home page"))
        #expect(phases[0].contains("Create app.py"))
        #expect(phases[1].contains("Phase 2: Complaints board"))
        #expect(phases[1].contains("/complaints"))
        // The regression this fix targets: phase 1's text must not have ended
        // up concatenated into phase 2's block, nor vanished into preamble.
        #expect(!phases[1].contains("Create app.py"))
    }

    // MARK: - no regression on the baseline (host spec fixtures)

    /// Every host spec fixture already opens with a title line before its
    /// first `## Phase` heading — the shape the *original*, unfixed splitter
    /// already handled correctly. The fix must not perturb this: the offset-0
    /// guard only fires when the text begins with `"## Phase "` itself, which
    /// none of these do.
    @Test func hostSpecFixtureMatchesUnfixedSplitterByteForByte() throws {
        let text = try fixtureSpec("roadmap")

        // The behavior of the *original* main.swift splitter, reproduced here
        // literally (not by calling the fixed `decompose`), so this test would
        // fail if the fix ever changed output for a text that doesn't need it.
        let legacyParts = text.components(separatedBy: "\n## Phase ")
        let legacyPreamble = legacyParts.first ?? ""
        let legacyPhases = legacyParts.dropFirst().map { "## Phase " + $0 }

        let (preamble, phases) = decompose(text)

        #expect(preamble == legacyPreamble)
        #expect(phases == legacyPhases)
        #expect(phases.count == 3)  // roadmap.md: Home Page, Complaints Board, Add Complaint
    }

    @Test func hostSpecFixtureDoesNotBeginWithPhaseHeading() throws {
        let text = try fixtureSpec("roadmap")
        // Precondition the whole test file rests on: this fixture is the
        // "already has a title line first" shape, not the offset-0 shape.
        #expect(!text.hasPrefix("## Phase "))
    }

    // MARK: - plain unit coverage

    @Test func noHeadingsYieldsZeroPhasesAndFullTextAsPreamble() {
        let (preamble, phases) = decompose("Just a paragraph of prose, no headings at all.")

        #expect(phases.isEmpty)
        #expect(preamble == "Just a paragraph of prose, no headings at all.")
    }

    @Test func emptyStringYieldsZeroPhases() {
        let (preamble, phases) = decompose("")

        #expect(phases.isEmpty)
        #expect(preamble.isEmpty)
    }
}
