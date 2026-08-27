// Markdown renderer for chat bubbles, backed by the Lakr233/MarkdownView fork
// (notatestuser/MarkdownView, see Package.swift provenance). This is the ONLY
// file that imports the renderer — the dependency seam.
//
// We render through the library's raw AppKit `MarkdownTextView` wrapped in our
// own `MarkdownNSText` representable, NOT the library's SwiftUI `MarkdownView`.
// That wrapper sizes itself with a GeometryReader plus an async height binding,
// which schedules a fresh layout pass on every pass; inside our
// LazyVStack-in-ScrollView the placement graph never converges → 100% main-thread
// spin in `LazySubviewPlacements.placeSubviews` (profiled in DS4 Control).
// `MarkdownNSText` reports height synchronously from `sizeThatFits` — width in,
// height out, in the same layout pass, no async binding — so layout converges in
// one pass. Selection, code highlighting, tables and math are still handled
// inside `MarkdownTextView`. (Provenance: agent-mode `MarkdownText.swift`.)

import AppKit
import MarkdownParser
import MarkdownView
import SwiftUI
import SwiftStarKit

/// Renders a complete (non-streaming) markdown string. Used for finished
/// assistant bubbles and the thinking disclosure. Streaming is safe too: the
/// transcript coalesces deltas in place, so this view re-renders on each
/// mutation (no separate streaming variant needed).
struct MarkdownText: View {
    let source: String

    init(_ source: String) { self.source = source }

    var body: some View {
        // `.default` theme: its colors are `NSColor.labelColor` / system dynamic
        // colors, so it tracks light/dark automatically.
        MarkdownNSText(markdown: MarkdownPreprocess.stripTaggedBlocks(
            MarkdownPreprocess.deLaTeXed(source)))
    }
}

extension MarkdownText {
    /// Debug-only smoke test for the SwiftPM resource-bundle load path — the
    /// one that crashed the shipped DS4 .app when Highlightr's/SwiftMath's
    /// bundles weren't resolvable (`Bundle.module` `fatalError`). Building a
    /// code block + math forces Highlightr and SwiftMath to load their resource
    /// bundles. Gated by the env var **and** an explicit `--markdown-selftest`
    /// argument (never the env alone: an inherited env var from a user shell
    /// must not silently exit the app at launch). Run the packaged binary as
    /// `DS4_SELFTEST_MARKDOWN=1 SwiftStar --markdown-selftest`. (Provenance:
    /// agent-mode `MarkdownText.swift`.)
    @MainActor static func runResourceSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["DS4_SELFTEST_MARKDOWN"] == "1",
            CommandLine.arguments.contains("--markdown-selftest")
        else { return }
        _ = NSApplication.shared  // math rendering reads NSApp.effectiveAppearance; set NSApp first
        let md = "```swift\nlet x = 1\n```\n\nInline math: $x^2 + 1$\n"
        _ = MarkdownTextView.PreprocessedContent(parserResult: MarkdownParser().parse(md), theme: .default)
        FileHandle.standardError.write(Data("DS4_SELFTEST_MARKDOWN: OK\n".utf8))
        exit(0)
    }
}

/// Renders one preprocessed markdown string through the library's raw AppKit
/// `MarkdownTextView`, reporting its height **synchronously** for the proposed
/// width via `sizeThatFits`. This is the freeze-safe sizing contract: SwiftUI
/// proposes a width, we return the matching height in the same layout pass — a
/// pure function of (width, content), no GeometryReader and no async height
/// binding, so the layout graph converges instead of re-scheduling itself.
/// `boundingSize(for:)` is cached by Litext per width, so the repeated calls
/// SwiftUI makes while scrolling are cheap.
private struct MarkdownNSText: NSViewRepresentable {
    let markdown: String

    func makeNSView(context _: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.theme = .default
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        let result = MarkdownParser().parse(markdown)
        let content = MarkdownTextView.PreprocessedContent(parserResult: result, theme: .default)
        view.setMarkdownManually(content)
        view.invalidateIntrinsicContentSize()
        context.coordinator.measuredWidth = -1  // content changed → next measure is real, not cached
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        // `boundingSize` → `LTXLabel.intrinsicContentSize` runs a full CoreText
        // framesetter pass and is NOT cached by the label; SwiftUI probes
        // `sizeThatFits` many times per layout and the bottom-follow re-lays-out
        // constantly, so measuring on every call re-typesets the whole document
        // and pegs CoreText (profiled). Cache the height per width and re-measure
        // only when the streamed text changed (`measuredWidth` is reset in
        // `updateNSView`); the frequent scroll/probe re-layouts then cost nothing.
        let cache = context.coordinator
        if abs(cache.measuredWidth - width) < 0.5 {
            return CGSize(width: width, height: cache.measuredHeight)
        }
        let height = ceil(nsView.boundingSize(for: width).height)
        cache.measuredWidth = width
        cache.measuredHeight = height
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        var lastMarkdown = ""
        var measuredWidth: CGFloat = -1
        var measuredHeight: CGFloat = 0
    }
}
