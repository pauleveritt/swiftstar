import Testing
import Foundation
@testable import SwiftStarKit

/// Replays the four real build-arm emissions from 2026-08-25 through the
/// harvest. These are unedited model output (`fixtures/agenttest/harvest/`,
/// reconstructed from each run's `wire.ndjson`), so they are the only evidence
/// that the lenient rules hold against what Mellum actually emits rather than
/// against hand-written examples.
///
/// Before the lenient harvest, three of these four runs harvested nothing and
/// the build arm scored 1/4.
struct HarvestCaptureReplayTests {
    /// The Phase-1 grant the build arm actually dispatches, copied from the
    /// captures' own `packet.json` — `models.py` included. An approximated grant
    /// would make these replays test a contract the real runs never ran under.
    private let allowlist = [
        "app.py", "models.py", "templates/base.html", "templates/home.html",
        "templates/complaints.html", "tests/test_app.py",
    ]

    private func capture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agenttest/harvest/\(name).txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func fencedCaptureHarvestsEveryFileAndAlsoRepeats() throws {
        // 20260825-162522 — the one run that fenced its blocks, and the only
        // build-arm success before this change. It must stay a success.
        //
        // It also repeats: after a complete pass over the granted set it emits
        // `app.py` and `complaints.html` twice more. So resampling-after-the-
        // answer is not unique to the run that hit the token wall — it is
        // present in the success too, which is why `degenerateRepetition` alone
        // must never be read as a failure. What separates the two is whether a
        // complete pass landed first.
        let r = LabeledBlockParser.parse(try capture("fenced"), writableFiles: allowlist)
        #expect(r.files.count == 6)
        #expect(r.degenerateRepetition)
        #expect(r.outOfGrantHeadings.isEmpty)
        #expect(r.files.map(\.path).contains("app.py"))
    }

    @Test func unfencedCaptureAHarvestsEveryFile() throws {
        // 20260825-171016 — five headings, zero fences, previously contractNotFollowed.
        let r = LabeledBlockParser.parse(try capture("unfenced-a"), writableFiles: allowlist)
        #expect(r.files.count == 5)
        #expect(!r.degenerateRepetition)
        #expect(r.files.first?.path == "app.py")
        #expect(r.files.first?.content.contains("from fastapi import FastAPI") == true)
    }

    @Test func unfencedCaptureBHarvestsEveryFileWithCommentsIntact() throws {
        // 20260825-171258 — same shape, and the run whose app.py carries a
        // `# In-memory storage` comment that must survive inside the body.
        let r = LabeledBlockParser.parse(try capture("unfenced-b"), writableFiles: allowlist)
        #expect(r.files.count == 5)
        #expect(!r.degenerateRepetition)
        let app = r.files.first { $0.path == "app.py" }
        #expect(app?.content.contains("# In-memory storage") == true)
        #expect(app?.content.contains("class Complaint") == true)
    }

    @Test func repeatedCaptureHarvestsTheFirstDraftAndFlagsRepetition() throws {
        // 20260825-171057 — ran to the 8192-token wall re-emitting the same four
        // headings eleven times. The first pass is a usable draft; everything
        // after the first repeat is resampling.
        let r = LabeledBlockParser.parse(try capture("repeated"), writableFiles: allowlist)
        #expect(r.degenerateRepetition)
        #expect(r.files.count == 4)
        #expect(r.duplicateCounts["app.py"] == 1)
        // Exactly one copy of each file, from the first pass only.
        #expect(Set(r.files.map(\.path)).count == r.files.count)
    }
}
