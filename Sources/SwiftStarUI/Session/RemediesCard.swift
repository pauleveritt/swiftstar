import SwiftUI
import SwiftStarKit

/// AN.3's remedies, at the end of the analysis fork: one checkbox per line,
/// unticked to start (D3). Done adds the ticked ones to the checkout's
/// instructions file once the main session is back (D4).
struct RemediesCard: View {
    let remedies: [Remedy]
    let ticked: Set<String>
    /// `AGENTS.md`, or `CLAUDE.md` when only it exists.
    let file: String
    let toggle: (String) -> Void
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Remedies for \(file)", systemImage: "wand.and.sparkles")
                .font(.scaled(.caption, base: fontSize).weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(remedies) { remedy in
                Toggle(isOn: Binding(get: { ticked.contains(remedy.line) }, set: { _ in toggle(remedy.line) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(remedy.label)
                            .font(.system(size: fontSize * 0.9))
                            .textSelection(.enabled)
                        if let why = remedy.fromEngine {
                            Text("From the engine's report: \(why)")
                                .font(.scaled(.caption2, base: fontSize))
                                .foregroundStyle(.secondary)
                        }
                        if remedy.alreadyThere {
                            Text("Already there")
                                .font(.scaled(.caption2, base: fontSize))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(remedy.alreadyThere)
            }
            Text("Done adds the ticked lines to \(file) in your checkout; commit it for the engine to read it.")
                .font(.scaled(.caption2, base: fontSize))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Remedies") {
    RemediesCard(
        remedies: [
            Remedy(line: "- Only call tools that exist in the provided toolset; there is no `run` tool — call `test`.",
                   fromEngine: nil, alreadyThere: false),
            Remedy(line: "- Never re-read a file you have already fully read just to verify an edit.",
                   fromEngine: nil, alreadyThere: false),
            Remedy(line: "- Run the tests with `swift test`.", fromEngine: "2 test runs in another form failed first",
                   alreadyThere: false),
            Remedy(line: "- Prefer `git diff` to re-reading a file.", fromEngine: nil, alreadyThere: true),
        ],
        ticked: ["- Run the tests with `swift test`."], file: "AGENTS.md", toggle: { _ in })
        .padding()
        .frame(width: 600)
}
