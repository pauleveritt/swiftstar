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
            Text(Self.metadataLine(card))
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
        let label = Label(Self.headerText(card), systemImage: Self.icon(for: card.tool.op))
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

    static func headerText(_ card: EngineToolCard) -> String {
        if let path = card.tool.path, !path.isEmpty {
            return "\(card.tool.op) \(path)"
        }
        return card.tool.op
    }

    /// State and duration: `running`, or `succeeded`/`failed` with the time.
    static func metadataLine(_ card: EngineToolCard) -> String {
        var parts: [String] = []
        switch card.ok {
        case nil: parts.append("running")
        case true?: parts.append("succeeded")
        case false?: parts.append("failed")
        }
        if let ms = card.durationMs, ms.isFinite, ms >= 0 {
            parts.append(duration(ms / 1000))
        }
        return parts.joined(separator: " · ")
    }

    private static func duration(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "%.1fs", seconds) }
        return String(format: "%.0fs", seconds)
    }

    static func icon(for op: String) -> String {
        switch op {
        case "bash", "bash_status", "bash_stop": return "terminal"
        case "write": return "doc.badge.plus"
        case "edit": return "square.and.pencil"
        case "ls": return "folder"
        case "read", "more": return "doc.text.magnifyingglass"
        case "grep": return "magnifyingglass"
        default: return "wrench.and.screwdriver"
        }
    }
}
