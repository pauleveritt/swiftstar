import QuickLook
import SwiftUI
import SwiftStarKit

/// A tool card: icon + `op path` header, the result preview in monospace, and
/// a facts line (state, duration, truncation). A card appears when the tool
/// starts and fills in as its end and result events arrive.
struct ToolCardView: View {
    let card: EngineToolCard
    let workspace: URL?
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    @State private var quickLookURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerView
            if let result = card.result, !result.preview.isEmpty {
                Text(result.preview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if card.result?.truncated == true {
                Text("Preview truncated")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(card.metadataLine)
                .font(.caption2)
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
        .quickLookPreview($quickLookURL)
    }

    /// Ops whose header becomes a tappable Quick Look button when they name a
    /// real file on disk.
    static let quickLookEligibleOps: Set<String> = ["write", "edit", "read"]

    @ViewBuilder
    private var headerView: some View {
        let label = Label(card.headerText, systemImage: card.icon)
            .font(.system(size: transcriptFontSize, weight: .semibold))
            .foregroundStyle(.primary)

        if Self.quickLookEligibleOps.contains(card.tool.op), let url = resolvedFileURL() {
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

    /// Resolves the tool's path against the workspace. nil if there is no
    /// path, or the file does not exist.
    private func resolvedFileURL() -> URL? {
        guard let workspace, let path = card.tool.path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, relativeTo: workspace)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

}

#Preview("Running") {
    ToolCardView(card: .previewRunning, workspace: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Succeeded") {
    ToolCardView(card: .previewSucceeded, workspace: nil)
        .padding()
        .frame(width: 420)
}

#Preview("Failed") {
    ToolCardView(card: .previewFailed, workspace: nil)
        .padding()
        .frame(width: 420)
}
