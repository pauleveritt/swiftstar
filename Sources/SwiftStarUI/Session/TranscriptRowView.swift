import AppKit
import SwiftUI
import SwiftStarKit

/// One transcript row, drawn according to its kind.
struct TranscriptRowView: View {
    let row: TranscriptRow
    /// The engine reported this (user) row's prompt as queued.
    let queued: Bool
    /// Offered on the last answer when the session can be analyzed (AN.2).
    var analyze: (() -> Void)? = nil
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        switch row {
        case .user(let text):
            PromptBubble(text: text, queued: queued)
        case .thinking(let text):
            ThinkingDisclosure(text: text)
        case .narration(let text):
            // Answers and narration link the files they name (SU.16, D4).
            MarkdownText(text, linksFiles: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .answer(let answer, let reply):
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(reply ?? answer.text, linksFiles: true)
                if reply != nil {
                    // The 27B's `finish` summary, under the full reply (SU.6a).
                    Text("Summary: \(answer.text)")
                        .font(.system(size: fontSize - 2))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    if let line = answer.summary {
                        // Engine telemetry, styled small and secondary so it never
                        // reads as part of the answer.
                        Text(line)
                            .font(.scaled(.caption2, base: fontSize))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    if let analyze {
                        Button("Analyze", action: analyze)
                            .buttonStyle(.link)
                            .font(.scaled(.caption2, base: fontSize))
                            .help("Report on this session, then ask about it in a copy")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let card):
            ToolCardView(card: card)
        case .system(let text):
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        case .error(let text):
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .report(let markdown):
            ReportCard(markdown: markdown)
        case .mentions(let attached, let missing):
            MentionsLine(attached: attached, missing: missing)
        case .divider(let text):
            HStack(spacing: 8) {
                VStack { Divider() }.frame(minWidth: 16)
                Text(text)
                    .font(.system(size: fontSize * 0.85, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
                VStack { Divider() }.frame(minWidth: 16)
            }
            .padding(.vertical, 4)
        }
    }
}

/// What a prompt's `@` mentions attached, small and secondary, and what they
/// missed, in red (SU.14, D3); under the prompt bubble, on its side. Each
/// attached file is its own link (SU.16, D4).
private struct MentionsLine: View {
    let attached: [String]
    let missing: [String]
    @Environment(\.fontSize) private var fontSize: CGFloat
    @Environment(\.fileLinkAction) private var links

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if !attached.isEmpty {
                // On one line when they fit, else one per line.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { attachments }
                    VStack(alignment: .trailing, spacing: 2) { attachments }
                }
            }
            ForEach(missing, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.scaled(.caption2, base: fontSize))
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Secondary text, but a linked name in the link color (D5).
    @ViewBuilder
    private var attachments: some View {
        Label("Attached", systemImage: "paperclip")
            .foregroundStyle(.secondary)
        ForEach(attached, id: \.self) { name in
            if let link = links?.resolve(name) {
                FileLinkButton(link: link) { Text(name) }
            } else {
                Text(name).foregroundStyle(.secondary)
            }
        }
    }
}

/// AN.1's session report, as a tinted card with a copy button, so it can be
/// pasted to another agent for a deeper look.
private struct ReportCard: View {
    let markdown: String
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Session report", systemImage: "doc.text.magnifyingglass")
                    .font(.scaled(.caption, base: fontSize).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Markdown") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                }
                .buttonStyle(.link)
                .font(.scaled(.caption, base: fontSize))
            }
            MarkdownText(markdown)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("System") {
    TranscriptRowView(row: .system("Conversation cleared"), queued: false)
        .padding()
        .frame(width: 420, alignment: .leading)
}

#Preview("Error") {
    TranscriptRowView(row: .error("ds4-dogfood exited with status 1"), queued: false)
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
        queued: false)
        .padding()
        .frame(width: 420)
}

#Preview("Answer with Analyze") {
    TranscriptRowView(
        row: .answer(EngineAnswer(
            text: "`SessionView` renders the transcript, composer, and status bar for one engine session.",
            contextUsed: 512, contextSize: 8192, durationMs: 1830)),
        queued: false, analyze: {})
        .padding()
        .frame(width: 420)
}

#Preview("Report card") {
    TranscriptRowView(row: .report(EngineTranscript.previewReport), queued: false)
        .padding()
        .frame(width: 560)
}

#Preview("Rebuilt after rewind") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(EngineTranscript.previewRewound.rows.enumerated()), id: \.offset) { _, row in
            TranscriptRowView(row: row, queued: false)
        }
    }
    .padding()
    .frame(width: 420, alignment: .leading)
}

#Preview("Switched model") {
    TranscriptRowView(
        row: .divider("Switched to qwen3.8-flash-next: new conversation, files kept"),
        queued: false)
        .padding()
        .frame(width: 420, alignment: .leading)
}

#Preview("Mentions") {
    VStack(spacing: 4) {
        TranscriptRowView(row: .user("Compare @Package.swift and @README.md with @nope.swift"), queued: false)
        TranscriptRowView(
            row: .mentions(attached: ["Package.swift", "README.md"], missing: ["nope.swift: no such file"]),
            queued: false)
    }
    .padding()
    .frame(width: 600)
    .previewFileLinks()
}

// SU.16: code spans that name a file link; one naming none, or a bare name
// two files share, stays plain.
#Preview("Answer with file links") {
    TranscriptRowView(
        row: .answer(EngineAnswer(
            text: """
                `Package.swift` declares the targets, and `EngineSession.swift` runs the engine \
                (`Sources/SwiftStarEngine/EngineSession.swift:42`). `missing.swift` isn't in the repository.

                | File | Role |
                |---|---|
                | `README.md` | the front door |
                """,
            contextUsed: 512, contextSize: 8192, durationMs: 1830)),
        queued: false)
        .padding()
        .frame(width: 520)
        .previewFileLinks()
}
