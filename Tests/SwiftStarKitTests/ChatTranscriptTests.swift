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
        #expect(transcript.rows == [
            .reasoning("think"),
            .content("Hello"),
            .content(" world"),
            .finished,
        ])
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
