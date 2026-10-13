import SwiftUI
import SwiftStarKit

/// Shown above the transcript while an analysis runs in its fork (AN.2):
/// says the session is a copy, and Done returns to the original. Done has no
/// keyboard shortcut: it ends the fork, which an easy key shouldn't do.
struct AnalysisBanner: View {
    /// Done would act now (the fork is idle at `input`).
    let canFinish: Bool
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
                .disabled(!canFinish)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
    }
}

#Preview("Analysis banner") {
    AnalysisBanner(canFinish: true, done: {})
        .frame(width: 600)
}

#Preview("Analysis banner, busy") {
    AnalysisBanner(canFinish: false, done: {})
        .frame(width: 600)
}
