import Testing
@testable import SwiftStarKit

struct ChatTranscriptTests {
    @Test func mapsEventsToRows() {
        var transcript = ChatTranscript()
        transcript.apply(.roleAssistant)
        transcript.apply(.reasoning("think"))
        transcript.apply(.content("Hello"))
        transcript.apply(.content(" world"))
        transcript.apply(.finish(.stop))
        transcript.apply(.done)
        // Consecutive content deltas coalesce into one row.
        #expect(transcript.rows == [
            .reasoning("think"),
            .content("Hello world"),
            .finished,
        ])
    }

    @Test func nonStopFinishStillMarksFinished() {
        var transcript = ChatTranscript()
        transcript.apply(.finish(.other("length")))
        #expect(transcript.rows == [.finished])
    }

    @Test func systemAndWireRowsInterleaveInOrder() {
        var transcript = ChatTranscript()
        transcript.apply(.content("a"))
        transcript.appendSystem("engine restarted")
        transcript.apply(.content("b"))
        #expect(transcript.rows == [.content("a"), .system("engine restarted"), .content("b")])
    }

    @Test func ignoresUnmodeledEvents() {
        var transcript = ChatTranscript()
        transcript.apply(.ignored("{\"future\":true}"))
        #expect(transcript.rows.isEmpty)
    }

    @Test func systemMessagesAppend() {
        var transcript = ChatTranscript()
        transcript.appendSystem("engine ready")
        #expect(transcript.rows == [.system("engine ready")])
    }
}
