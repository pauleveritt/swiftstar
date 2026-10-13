import SwiftUI
import SwiftStarKit

/// The session's transcript, scrolled to the newest row.
struct TranscriptView: View {
    let transcript: EngineTranscript
    /// Where the tool cards' relative paths resolve (Quick Look).
    let source: URL?
    /// Analyze, offered on the last answer only (AN.2); nil when not offered.
    var analyze: (() -> Void)? = nil
    /// Rows from here on belong to an analysis, and carry its tint.
    var analysisFirstRow: Int? = nil

    var body: some View {
        let lastAnswer = transcript.rows.lastIndex { if case .answer = $0 { true } else { false } }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Rows are keyed by offset: the transcript only appends
                // rows (a tool card fills in place), so an offset is a
                // stable identity for a row's whole lifetime.
                ForEach(Array(transcript.rows.enumerated()), id: \.offset) { index, row in
                    TranscriptRowView(
                        row: row, queued: transcript.isPending(rowAt: index), source: source,
                        analyze: index == lastAnswer ? analyze : nil)
                        .modifier(AnalysisRule(active: analysisFirstRow.map { index >= $0 } ?? false))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// The tinted leading rule on an analysis's rows: they go away at Done.
private struct AnalysisRule: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.accentColor.opacity(0.5)).frame(width: 3)
                }
        } else {
            content
        }
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

#Preview("Analyzing") {
    TranscriptView(
        transcript: EngineSessionModel.previewAnalyzing.transcript, source: nil,
        analysisFirstRow: EngineSessionModel.previewAnalyzing.analysis?.firstRow)
        .frame(width: 600, height: 1000)
}
