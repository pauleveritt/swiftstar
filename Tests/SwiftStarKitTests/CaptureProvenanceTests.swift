import Testing
import Foundation
@testable import SwiftStarKit

/// Item 6 (P22 cleanup): the shared `provenance.md` renderer behind
/// `AgentController`'s live-session provenance and `swiftstar-drive`'s
/// `CaptureWriter` — same shape (title, bulleted facts, closing note),
/// different facts per producer.
struct CaptureProvenanceTests {
    @Test func rendersTitleFactsAndClosingNoteInOrder() {
        let text = CaptureProvenance.render(
            title: "Example provenance",
            facts: [
                .init("Model", "`m.gguf`"),
                .init("Context", "1024"),
            ],
            closingNote: "A closing note.")
        #expect(text == """
        # Example provenance

        - Model: `m.gguf`
        - Context: 1024

        A closing note.
        """)
    }

    @Test func startedAtFactFormatsAsISO8601() {
        let fact = CaptureProvenance.startedAtFact(Date(timeIntervalSince1970: 1_700_000_000))
        #expect(fact.label == "Started (wall-clock)")
        #expect(fact.value == ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    @Test func emptyFactsRendersJustTheTitleAndClosingNote() {
        // No facts -> the fact-list line is empty, so the title and closing
        // note end up separated by a blank fact line plus the two structural
        // blank lines (four newlines between them).
        let text = CaptureProvenance.render(title: "Empty", facts: [], closingNote: "Note.")
        #expect(text == "# Empty\n\n\n\nNote.")
    }
}
