import SwiftUI
import SwiftStarKit

/// One transcript row, drawn according to its kind.
struct TranscriptRowView: View {
    let row: TranscriptRow
    /// The engine reported this (user) row's prompt as queued.
    let queued: Bool
    /// Where the tool cards' relative paths resolve (Quick Look).
    let source: URL?
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
        case .answer(let answer, let reply):
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(reply ?? answer.text)
                if reply != nil {
                    // The 27B's `finish` summary, under the full reply (SU.6a).
                    Text("Summary: \(answer.text)")
                        .font(.system(size: transcriptFontSize - 2))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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
            ToolCardView(card: card, source: source)
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
        case .divider(let text):
            HStack(spacing: 8) {
                VStack { Divider() }.frame(minWidth: 16)
                Text(text)
                    .font(.system(size: transcriptFontSize * 0.85, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
                VStack { Divider() }.frame(minWidth: 16)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview("System") {
    TranscriptRowView(row: .system("Conversation cleared"), queued: false, source: nil)
        .padding()
        .frame(width: 420, alignment: .leading)
}

#Preview("Error") {
    TranscriptRowView(row: .error("ds4-dogfood exited with status 1"), queued: false, source: nil)
        .padding()
        .frame(width: 420, alignment: .leading)
}

#Preview("Answer with summary") {
    TranscriptRowView(
        row: .answer(
            EngineAnswer(
                text: "Six targets: three libraries, one executable, two test targets.",
                contextUsed: 512, contextSize: 8192, durationMs: 1830),
            reply: "`Package.swift` declares **six targets**:\n\n1. `SwiftStarKit`\n2. `SwiftStarEngine`\n3. `SwiftStarUI`"),
        queued: false, source: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Rebuilt after rewind") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(EngineTranscript.previewRewound.rows.enumerated()), id: \.offset) { _, row in
            TranscriptRowView(row: row, queued: false, source: nil)
        }
    }
    .padding()
    .frame(width: 420, alignment: .leading)
}

#Preview("Switched model") {
    TranscriptRowView(
        row: .divider("Switched to qwen3.8-flash-next: new conversation, files kept"),
        queued: false, source: nil)
        .padding()
        .frame(width: 420, alignment: .leading)
}
