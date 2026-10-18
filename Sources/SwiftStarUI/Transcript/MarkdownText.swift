// Markdown renderer for chat bubbles, backed by the Lakr233/MarkdownView fork
// (pauleveritt/MarkdownView, see Package.swift provenance). This is the ONLY
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

/// Renders one complete markdown string: an answer, a narration or a thinking
/// disclosure. Rows arrive whole (the engine reports per pause, not per token).
struct MarkdownText: View {
    let source: String
    /// Inline code spans that name a file become links to it (SU.16, D4):
    /// answers and narration, not the report card or thinking.
    let linksFiles: Bool
    @Environment(\.fontSize) private var fontSize: CGFloat
    @Environment(\.fileLinkAction) private var links

    init(_ source: String, linksFiles: Bool = false) {
        self.source = source
        self.linksFiles = linksFiles
    }

    public var body: some View {
        // `.default` theme: its colors are `NSColor.labelColor` / system dynamic
        // colors, so it tracks light/dark automatically. The body font is
        // aligned to the environment's transcript size, so the Settings slider
        // re-typesets the prose live (a size change rebuilds the theme and
        // re-parses — see `MarkdownNSText.updateNSView`).
        let text = MarkdownPreprocess.deLaTeXed(source)
        let links = linksFiles ? links : nil
        MarkdownNSText(
            markdown: links.map { action in MarkdownPreprocess.fileLinks(text) { action.resolve($0)?.path } } ?? text,
            fontSize: fontSize,
            onLink: { destination in
                // A file link opens Quick Look (D7); a web link, the browser.
                if let path = FileLink.path(fromDestination: destination), let link = links?.resolve(path) {
                    // The label made itself first responder on the click, and
                    // Quick Look finds its controller through the responder
                    // chain, where the label isn't: open after letting go of it.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    DispatchQueue.main.async { links?.open(link) }
                } else if let url = URL(string: destination), ["http", "https"].contains(url.scheme) {
                    NSWorkspace.shared.open(url)
                }
            })
    }
}

/// Code colored as answers' code blocks are (SU.15): the fork's highlighter,
/// its Xcode-theme ranges as SwiftUI colors that follow light and dark. Here
/// because this is the one file that imports the renderer. A nil language,
/// or one Highlightr doesn't know, leaves the text plain.
enum CodeColoring {
    static func attributed(_ text: String, language: String?) -> AttributedString {
        var result = AttributedString(text)
        guard let language else { return result }
        let map = CodeHighlighter.current.highlight(key: nil, content: text, language: language)
        for (range, color) in map {
            guard let stringRange = Range(range, in: text),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].foregroundColor = Color(nsColor: color)
        }
        return result
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
    let fontSize: CGFloat
    /// A clicked link's destination, as the parser stored it (a String).
    let onLink: (String) -> Void

    /// A theme with the conversation's body font aligned to `size`. `align(to:)`
    /// scales body/code/bold/italic/largeTitle/title from the fork's defaults.
    static func theme(for size: CGFloat) -> MarkdownTheme {
        var theme = MarkdownTheme.default
        theme.align(to: size)
        // Links in the system link color, as the tool cards' and attachments'
        // are (SU.16, D5); the fork's default highlight is orange.
        theme.colors.highlight = .linkColor
        return theme
    }

    func makeNSView(context _: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        // The fork's AppKit init never makes the view its label's delegate
        // (its UIKit init does), so a link click found its region and told
        // no one: `linkHandler` never ran (SU.16, found in the gallery).
        view.textView.delegate = view
        view.theme = Self.theme(for: fontSize)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        // Before any content is set: a table's cells copy the handler when
        // they're built (the fork's `TextBuilder+Do.swift:190`), SU.16.
        let onLink = onLink
        view.linkHandler = { payload, _, _ in
            switch payload {
            case .url(let url): onLink(url.absoluteString)
            case .string(let string): onLink(string)
            }
        }
        // Re-apply when either the text OR the font size changed — a size
        // change alone must re-typeset (the Settings slider). The theme is
        // rebuilt so `setMarkdownManually` picks up the new fonts.
        let markdownChanged = context.coordinator.lastMarkdown != markdown
        let sizeChanged = context.coordinator.lastFontSize != fontSize
        guard markdownChanged || sizeChanged else { return }
        if markdownChanged { context.coordinator.lastMarkdown = markdown }
        if sizeChanged {
            context.coordinator.lastFontSize = fontSize
            view.theme = Self.theme(for: fontSize)
        }
        let result = MarkdownParser().parse(markdown)
        let content = MarkdownTextView.PreprocessedContent(parserResult: result, theme: view.theme)
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

    final class Coordinator {
        var lastMarkdown = ""
        var lastFontSize: CGFloat = -1
        var measuredWidth: CGFloat = -1
        var measuredHeight: CGFloat = 0
    }
}

#Preview("Markdown") {
    MarkdownText("""
    # Heading

    Some *emphasis*, **strong text** and `inline code`.

    ```swift
    let greeting = "Hello, SwiftStar"
    print(greeting)
    ```
    """)
    .padding()
    .frame(width: 420)
}

/// The markdown renderer's resource-bundle smoke test, run by `Tools/make-app.sh`
/// against the assembled app.
public enum MarkdownSelfTest {
    /// Debug-only smoke test for the SwiftPM resource-bundle load path — the
    /// one that crashed the shipped DS4 .app when Highlightr's/SwiftMath's
    /// bundles weren't resolvable (`Bundle.module` `fatalError`). Building a
    /// code block + math forces Highlightr and SwiftMath to load their resource
    /// bundles; reading `LocalizedText.copy` loads Litext's, which otherwise
    /// happens only at the transcript's first right-click (SU.6d). MarkdownView's
    /// own bundle holds an unused strings file that no code reads. Gated by the env var **and** an explicit `--markdown-selftest`
    /// argument (never the env alone: an inherited env var from a user shell
    /// must not silently exit the app at launch). Run the packaged binary as
    /// `DS4_SELFTEST_MARKDOWN=1 SwiftStar --markdown-selftest`.
    public static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["DS4_SELFTEST_MARKDOWN"] == "1",
            CommandLine.arguments.contains("--markdown-selftest")
        else { return }
        _ = NSApplication.shared  // math rendering reads NSApp.effectiveAppearance; set NSApp first
        let md = "```swift\nlet x = 1\n```\n\nInline math: $x^2 + 1$\n"
        _ = MarkdownTextView.PreprocessedContent(parserResult: MarkdownParser().parse(md), theme: .default)
        _ = LocalizedText.copy  // Litext, re-exported by MarkdownView
        FileHandle.standardError.write(Data("DS4_SELFTEST_MARKDOWN: OK\n".utf8))
        exit(0)
    }
}
