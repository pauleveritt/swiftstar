import QuickLook
import SwiftUI
import SwiftStarKit

/// A tool card: icon + `op path` header, the result preview in monospace, and
/// a facts line (state, duration, truncation). A card appears when the tool
/// starts and fills in as its end and result events arrive. A call the engine
/// declined is drawn greyed, with the engine's one line instead of a result.
struct ToolCardView: View {
    let card: EngineToolCard
    /// Where a relative tool path resolves: the session's git root.
    let source: URL?
    @Environment(\.fontSize) private var fontSize: CGFloat

    @State private var quickLookURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerView
            if let rejection = card.rejection {
                Text(rejection.text)
                    .font(.scaled(.caption, base: fontSize))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let result = card.result, !result.preview.isEmpty {
                Text(result.preview)
                    .font(.scaled(.caption, base: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if card.result?.truncated == true {
                Text("Preview truncated")
                    .font(.scaled(.caption2, base: fontSize))
                    .foregroundStyle(.secondary)
            }
            Text(card.metadataLine)
                .font(.scaled(.caption2, base: fontSize))
                .foregroundStyle(card.ok == false ? Color(nsColor: .systemRed) : .secondary)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .opacity(card.rejection == nil ? 1 : 0.7)
        .quickLookPreview($quickLookURL)
    }

    /// Ops whose header becomes a tappable Quick Look button when they name a
    /// real file on disk.
    static let quickLookEligibleOps: Set<String> = ["write", "edit", "read"]

    @ViewBuilder
    private var headerView: some View {
        let label = Label(card.headerText, systemImage: card.icon)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(card.rejection == nil ? .primary : .secondary)

        if card.rejection == nil, Self.quickLookEligibleOps.contains(card.tool.op),
           let url = resolvedFileURL() {
            Button {
                quickLookURL = url
            } label: {
                label
            }
            .buttonStyle(.plain)
            .help("Quick Look \(url.lastPathComponent)")
        } else {
            label
        }
    }

    /// The card's file under the source, if it exists on disk.
    private func resolvedFileURL() -> URL? {
        guard let url = card.fileURL(source: source) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

}

#Preview("Running") {
    ToolCardView(card: .previewRunning, source: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Succeeded") {
    ToolCardView(card: .previewSucceeded, source: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Failed") {
    ToolCardView(card: .previewFailed, source: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Declined") {
    ToolCardView(card: .previewDeclined, source: nil)
        .padding()
        .frame(width: 420)
}
