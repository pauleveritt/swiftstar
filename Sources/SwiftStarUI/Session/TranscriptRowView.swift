import AppKit
import SwiftUI
import SwiftStarKit

/// One transcript row, drawn according to its kind.
struct TranscriptRowView: View {
    let row: TranscriptRow
    /// The engine has not started a turn for this (user) row yet.
    let queued: Bool
    /// Where the tool cards' relative paths resolve (Quick Look).
    let source: URL?
    /// Offered on the last answer when the session can be analyzed (AN.2).
    var analyze: (() -> Void)? = nil
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
                HStack(spacing: 8) {
                    if let line = answer.summary {
                        // Engine telemetry, styled small and secondary so it never
                        // reads as part of the answer.
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    if let analyze {
                        Button("Analyze", action: analyze)
                            .buttonStyle(.link)
                            .font(.caption2)
                            .help("Report on this session, then ask about it in a copy")
                    }
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
        case .report(let markdown):
            ReportCard(markdown: markdown)
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

/// AN.1's session report, as a tinted card with a copy button, so it can be
/// pasted to another agent for a deeper look.
private struct ReportCard: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Session report", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            MarkdownText(markdown)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
        row: .answer(EngineAnswer(
            text: "`SessionView` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)),
        queued: false, source: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Answer with Analyze") {
    TranscriptRowView(
        row: .answer(EngineAnswer(
            text: "`SessionView` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)),
        queued: false, source: nil, analyze: {})
        .padding()
        .frame(width: 420)
}

#Preview("Report card") {
    TranscriptRowView(row: .report(EngineTranscript.previewReport), queued: false, source: nil)
        .padding()
        .frame(width: 560)
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
