import SwiftUI
import SwiftStarKit

/// The user's echoed prompt — a right-aligned, accent-filled pill. Ported from
/// the DS4 Control agent window's `AgentPromptBubble` (agent-mode worktree).
struct AgentPromptBubble: View {
    let text: String
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: transcriptFontSize))
                .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlAccentColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
        }
    }
}

/// Model reasoning, hidden by default in a collapsed disclosure. The reasoning
/// is rendered only when expanded, so collapsed reasoning costs nothing to lay
/// out (the deltas just accumulate in the row). Ported from the DS4 Control
/// agent window's `ThinkingDisclosure`.
struct ThinkingDisclosure: View {
    let text: String
    @State private var expanded = false
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: transcriptFontSize - 2))
                        .frame(width: 10)
                    Label("Thinking", systemImage: "brain")
                        .font(.system(size: transcriptFontSize))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                MarkdownText(text)
                    .opacity(0.9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// A worker's final answer surfaced by `/chat` — a delegated artifact, so it
/// renders as its own panel with a provenance header, not as the main agent's
/// prose. The markdown body is the worker's text; the header carries the
/// worker id.
struct ConsultedAnswerView: View {
    let worker: WorkerId
    let text: String
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Worker answer · worker \(worker.rawValue)",
                  systemImage: "arrow.triangle.branch")
                .font(.system(size: transcriptFontSize).weight(.medium))
                .foregroundStyle(.secondary)
            MarkdownText(text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
