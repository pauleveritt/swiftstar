import QuickLook
import SwiftUI
import SwiftStarKit

/// The rich tool card, ported from the DS4 Control agent window's
/// `AgentItemView.card(call:)`: icon + header row (the `$ command` or
/// `name path` inline), then a body driven by the call's own structured
/// params — never by re-parsing scraped text. A card appears the moment its
/// call's name is known and updates live as the call's params stream in;
/// `card.finished` (not transcript-tail-ness) gates syntax highlighting, so a
/// finished card re-typesets immediately even when it sits as the last row.
struct AgentToolCardView: View {
    let card: ToolCard
    let workspace: URL
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    @State private var quickLookURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerView
            if !Self.isBodyEmpty(card) {
                cardBody
            }
            if let message = card.status {
                // The engine's own diagnostic strings end in `\n` ("[tool call
                // interrupted]\n") — trimmed here for display only, so the red
                // banner does not carry a trailing blank line.
                Text(Self.trimmedForDisplay(message))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    /// Tool calls whose header becomes a tappable Quick Look button when they
    /// name a real file on disk. `read`'s icon already implies "look at this
    /// file" — it must actually do that, matching `write`/`edit`.
    static let quickLookEligibleToolNames: Set<String> = ["write", "edit", "read"]

    @ViewBuilder
    private var headerView: some View {
        let label = Label(Self.headerText(card), systemImage: Self.icon(for: card.name))
            .font(.system(size: transcriptFontSize, weight: .semibold))
            .foregroundStyle(.primary)

        if Self.quickLookEligibleToolNames.contains(card.name), let url = resolvedFileURL() {
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

    /// Resolves `card.path` against the session's workspace. nil if there is no
    /// path, or the resolved file does not exist — mid-stream the file may not
    /// be written yet.
    private func resolvedFileURL() -> URL? {
        guard let path = card.path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, relativeTo: workspace)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Strips only *trailing* newlines — display-only; neither leading nor
    /// interior whitespace is touched, so a multi-line message keeps its shape.
    static func trimmedForDisplay(_ s: String) -> String {
        var result = Substring(s)
        while let last = result.last, last == "\n" || last == "\r" {
            result.removeLast()
        }
        return String(result)
    }

    /// `bash` shows its command inline (`$ ls -la`); a `path`-kinded param
    /// shows `name path`; everything else is the bare tool name. Driven entirely
    /// by `card.name` / `card.path` — no header string to prefix-match or parse.
    static func headerText(_ card: ToolCard) -> String {
        if card.name == "bash",
            let command = card.params.first(where: { $0.kind == "bash_command" })?.value
        {
            return "$ \(command)"
        }
        if let path = card.path {
            return "\(card.name) \(path)"
        }
        return card.name
    }

    /// True when this call will render nothing below its header: no param worth
    /// showing (path and the bash command are already in the header) and no
    /// output. Most tool calls end up here — only the bash family produces
    /// `output`, and `read`/`list`/`search` never do. This is the finished,
    /// correct state for those calls, not a pending one, so the card must render
    /// no empty region or placeholder for it.
    static func isBodyEmpty(_ card: ToolCard) -> Bool {
        Self.visibleParams(card).isEmpty && card.output == nil
    }

    /// Every param except the ones already surfaced in the header.
    static func visibleParams(_ card: ToolCard) -> [ToolParam] {
        card.params.filter { $0.kind != "path" && $0.kind != "bash_command" }
    }

    @ViewBuilder
    private var cardBody: some View {
        let params = Self.visibleParams(card)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(params.enumerated()), id: \.offset) { _, param in
                paramView(param)
            }
            if let output = card.output {
                if !params.isEmpty { Divider().opacity(0.3) }
                // Tool *execution* output (a shell command's stdout) — plain
                // monospace, never through the markdown renderer. This is a
                // command's stdout, not model prose: markdown-formatting it
                // would turn a `#`-prefixed output line into a heading.
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Styled by `param.kind`: `content` and `edit`'s `old`/`new` get dedicated
    /// renderers, everything else is a compact `name: value` line — identified
    /// by `name` for same-kind params (`start_line` and `max_lines` are both
    /// `offset`).
    @ViewBuilder
    private func paramView(_ param: ToolParam) -> some View {
        switch param.kind {
        case "content":
            contentView(param.value)
        case "diff_old":
            diffBlock(param.value, prefix: "−", tint: .systemRed)
        case "diff_new":
            diffBlock(param.value, prefix: "+", tint: .systemGreen)
        case "path", "bash_command":
            EmptyView()  // already surfaced in the header
        default:
            Text("\(param.name): \(param.value)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A `.content` param (e.g. `write`'s file body) syntax-highlighted by the
    /// path's extension once the call has finished; plain monospace while it is
    /// still streaming in. Gated on `card.finished`, not tail-ness: a card can
    /// finish and sit as the last row with no new item ever arriving to
    /// "unstick" it.
    @ViewBuilder
    private func contentView(_ value: String) -> some View {
        if card.finished {
            MarkdownText(MarkdownPreprocess.fenced(
                value, language: MarkdownPreprocess.language(forPath: card.path)))
        } else {
            Text(value)
                .font(.system(size: transcriptFontSize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `.diffOld`/`.diffNew` drive coloring directly — the parameter's own kind,
    /// not a first-character `-`/`+` heuristic over scraped diff text. `old`/
    /// `new` are each the whole pre-/post-edit value, so every line of a param
    /// is tinted uniformly; the leading glyph is a display-only nod to the
    /// familiar diff look.
    private func diffBlock(_ value: String, prefix: String, tint: NSColor) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(value.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                Text("\(prefix) \(line)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(nsColor: tint))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: tint).opacity(0.12))
            }
        }
        .textSelection(.enabled)
    }

    static func icon(for toolName: String) -> String {
        switch toolName {
        case "bash", "bash_status", "bash_stop": return "terminal"
        case "write": return "doc.badge.plus"
        case "edit": return "square.and.pencil"
        case "list": return "folder"
        case "read", "more": return "doc.text.magnifyingglass"
        case "search": return "magnifyingglass"
        case "google_search": return "globe"
        case "visit_page": return "safari"
        default: return "wrench.and.screwdriver"
        }
    }
}
