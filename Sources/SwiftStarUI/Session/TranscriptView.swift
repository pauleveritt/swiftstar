import QuickLook
import SwiftUI
import SwiftStarKit

/// The session's transcript, scrolled to the newest row.
struct TranscriptView: View {
    let transcript: EngineTranscript
    /// How the rows' file names resolve (SU.16); nil before a session has a
    /// checkout, and then nothing links.
    let links: FileLinkLookup?
    /// Analyze, offered on the last answer only (AN.2); nil when not offered.
    var analyze: (() -> Void)? = nil
    /// Rows from here on belong to an analysis, and carry its tint.
    var analysisFirstRow: Int? = nil

    /// The one Quick Look every row's links open (SU.16, D6).
    @State private var quickLook: URL?

    var body: some View {
        rows
            .environment(\.fileLinkAction, links.map { lookup in
                FileLinkAction(resolve: lookup.resolve, open: { quickLook = $0.url })
            })
            .quickLookPreview($quickLook)
    }

    @ViewBuilder
    private var rows: some View {
        let lastAnswer = transcript.rows.lastIndex { if case .answer = $0 { true } else { false } }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Rows are keyed by offset: the transcript only appends
                // rows (a tool card fills in place), so an offset is a
                // stable identity for a row's whole lifetime.
                ForEach(Array(transcript.rows.enumerated()), id: \.offset) { index, row in
                    TranscriptRowView(
                        row: row, queued: transcript.isQueued(rowAt: index),
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
    TranscriptView(transcript: EngineController.previewRunning.transcript, links: nil)
        .frame(width: 600, height: 400)
}

#Preview("Empty") {
    TranscriptView(transcript: EngineTranscript(), links: nil)
        .frame(width: 600, height: 200)
}

#Preview("Analyzing") {
    TranscriptView(
        transcript: EngineSessionModel.previewAnalyzing.transcript, links: nil,
        analysisFirstRow: EngineSessionModel.previewAnalyzing.analysis?.firstRow)
        .frame(width: 600, height: 1000)
}
