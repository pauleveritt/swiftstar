import SwiftUI

/// The user's echoed prompt — a right-aligned, accent-filled pill.
struct PromptBubble: View {
    let text: String
    /// The engine reported this prompt as queued.
    var queued = false
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 60)
            if queued {
                Text("Queued")
                    .font(.system(size: fontSize - 2))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlAccentColor))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
        }
    }
}


#Preview("PromptBubble") {
    PromptBubble(text: "Summarize SessionView.swift")
        .padding()
        .frame(width: 420)
}

#Preview("PromptBubble queued") {
    PromptBubble(text: "Summarize SessionView.swift", queued: true)
        .padding()
        .frame(width: 420)
}
