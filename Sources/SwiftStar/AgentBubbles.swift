import SwiftUI
import SwiftStarKit

/// The user's echoed prompt — a right-aligned, accent-filled pill. Ported from
/// the DS4 Control agent window's `AgentPromptBubble` (agent-mode worktree).
struct AgentPromptBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 10)
                    Label("Thinking", systemImage: "brain")
                        .font(.caption)
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
