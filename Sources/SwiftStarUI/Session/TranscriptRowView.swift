import SwiftUI
import SwiftStarKit

/// One transcript row, drawn according to its kind.
struct TranscriptRowView: View {
    let row: TranscriptRow
    /// The engine has not started a turn for this (user) row yet.
    let queued: Bool
    let workspace: URL?
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        switch row {
        case .user(let text):
            PromptBubble(text: text, queued: queued)
        case .thinking(let text):
            ThinkingDisclosure(text: text)
        case .narration(let text):
            MarkdownText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .answer(let answer):
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(answer.text)
                if let line = answer.summary {
                    // Engine telemetry, styled small and secondary so it never
                    // reads as part of the answer.
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let card):
            ToolCardView(card: card, workspace: workspace)
        case .system(let text):
            Text(text)
                .font(.system(size: transcriptFontSize))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        case .error(let text):
            Text(text)
                .font(.system(size: transcriptFontSize))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

#Preview("System") {
    TranscriptRowView(row: .system("Conversation cleared"), queued: false, workspace: nil)
        .padding()
        .frame(width: 420, alignment: .leading)
}

#Preview("Error") {
    TranscriptRowView(row: .error("ds4-dogfood exited with status 1"), queued: false, workspace: nil)
        .padding()
        .frame(width: 420, alignment: .leading)
}

#Preview("Answer with summary") {
    TranscriptRowView(
        row: .answer(EngineAnswer(
            text: "`SessionView` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)),
        queued: false, workspace: nil)
        .padding()
        .frame(width: 420)
}
