import SwiftUI

/// The user's echoed prompt — a right-aligned, accent-filled pill.
struct PromptBubble: View {
    let text: String
    /// The engine has not started a turn for this prompt yet.
    var queued = false
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 60)
            if queued {
                Text("Queued")
                    .font(.system(size: transcriptFontSize - 2))
                    .foregroundStyle(.secondary)
            }
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
/// out.
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
