import SwiftUI
import SwiftStarKit

/// The session's transcript, scrolled to the newest row.
struct TranscriptView: View {
    let transcript: EngineTranscript
    /// Where the tool cards' relative paths resolve (Quick Look).
    let source: URL?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Rows are keyed by offset: the transcript only appends
                // rows (a tool card fills in place), so an offset is a
                // stable identity for a row's whole lifetime.
                ForEach(Array(transcript.rows.enumerated()), id: \.offset) { index, row in
                    TranscriptRowView(row: row, queued: transcript.isQueued(rowAt: index), source: source)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
    }
}

#Preview("Running") {
    TranscriptView(transcript: EngineController.previewRunning.transcript, source: nil)
        .frame(width: 600, height: 400)
}

#Preview("Empty") {
    TranscriptView(transcript: EngineTranscript(), source: nil)
        .frame(width: 600, height: 200)
}
