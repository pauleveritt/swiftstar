import SwiftUI

/// Model reasoning, hidden by default in a collapsed disclosure. The reasoning
/// is rendered only when expanded, so collapsed reasoning costs nothing to lay
/// out.
struct ThinkingDisclosure: View {
    let text: String
    @State private var expanded = false
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: fontSize - 2))
                        .frame(width: 10)
                    Label("Thinking", systemImage: "brain")
                        .font(.system(size: fontSize))
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

#Preview("ThinkingDisclosure") {
    ThinkingDisclosure(text: "The user wants a summary, so I should read the file first.")
        .padding()
        .frame(width: 420)
}
