import SwiftUI
import SwiftStarKit

/// Shown above the transcript while an analysis runs in its fork (AN.2):
/// says the session is a copy, and Done returns to the original.
struct AnalysisBanner: View {
    let done: () -> Void
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(.tint)
            Text(EngineAnalysis.banner)
                .font(.system(size: transcriptFontSize * 0.9))
            Spacer()
            Button("Done", action: done)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
    }
}

#Preview("Analysis banner") {
    AnalysisBanner(done: {})
        .frame(width: 600)
}
