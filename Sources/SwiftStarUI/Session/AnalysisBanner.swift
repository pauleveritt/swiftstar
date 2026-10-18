import SwiftUI
import SwiftStarKit

/// Shown above the transcript while an analysis runs in its fork (AN.2):
/// says the session is a copy, and Done returns to the original. Done has no
/// keyboard shortcut: it ends the fork, which an easy key shouldn't do.
struct AnalysisBanner: View {
    /// Done would act now (the fork is idle at `input`).
    let canFinish: Bool
    /// "Done", or what Done will add (AN.3, D3).
    var title = "Done"
    let done: () -> Void
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle.fill")
                .foregroundStyle(.tint)
            Text(EngineAnalysis.banner)
                .font(.system(size: fontSize * 0.9))
            Spacer()
            Button(title, action: done)
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

// AN.3, D3: Done says what it will add.
#Preview("Analysis banner, remedies ticked") {
    AnalysisBanner(canFinish: true, title: Remedies.doneTitle(count: 2, file: "AGENTS.md"), done: {})
        .frame(width: 600)
}
