import SwiftUI
import SwiftStarKit

/// A tool card: icon + `op path` header, the result preview in monospace, and
/// a facts line (state, duration, truncation). A card appears when the tool
/// starts and fills in as its end and result events arrive. A call the engine
/// declined is drawn greyed, with the engine's one line instead of a result.
struct ToolCardView: View {
    let card: EngineToolCard
    @Environment(\.fontSize) private var fontSize: CGFloat
    /// The transcript's file links (SU.16): the header of a file's card is one.
    @Environment(\.fileLinkAction) private var links

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
                // Colored by the file's language (SU.15); a Markdown file as
                // colored raw text, what the model read.
                Text(CodeColoring.attributed(result.preview, language: card.resultLanguage))
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
                // Red for a failed call, and for a bash run that exited
                // non-zero, which the engine reports as ok (SU.18, D2).
                .foregroundStyle(card.failed ? Color(nsColor: .systemRed) : .secondary)
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
    }

    /// Ops whose header links to its file when it names a real one (SU.16,
    /// D4): `grep` and `ls` paths can be directories.
    static let quickLookEligibleOps: Set<String> = ["write", "edit", "read"]

    @ViewBuilder
    private var headerView: some View {
        let label = Label(card.headerText, systemImage: card.icon)
            .font(.system(size: fontSize, weight: .semibold))

        if card.rejection == nil, Self.quickLookEligibleOps.contains(card.tool.op),
           let path = card.tool.path, let link = links?.resolve(path) {
            // The link color, in place of `.primary` (D5).
            FileLinkButton(link: link) { label }
        } else {
            label.foregroundStyle(card.rejection == nil ? .primary : .secondary)
        }
    }
}

#Preview("Running") {
    ToolCardView(card: .previewRunning)
        .padding()
        .frame(width: 420)
}

#Preview("Succeeded") {
    ToolCardView(card: .previewSucceeded)
        .padding()
        .frame(width: 420)
}

// SU.16, D5: the header of a card whose file exists is a link.
#Preview("Link header") {
    ToolCardView(card: .previewSucceeded)
        .padding()
        .frame(width: 420)
        .previewFileLinks()
}

#Preview("Failed") {
    ToolCardView(card: .previewFailed)
        .padding()
        .frame(width: 420)
}

#Preview("Declined") {
    ToolCardView(card: .previewDeclined)
        .padding()
        .frame(width: 420)
}

// SU.15: one card per language the owner's screenshots showed.
#Preview("Python, Markdown, TOML") {
    VStack(spacing: 8) {
        ToolCardView(card: .previewRead("app.py", """
            from fastapi import FastAPI

            app = FastAPI()  # the complaints app

            @app.get("/")
            def index() -> dict[str, str]:
                return {"status": "ok"}
            """))
        ToolCardView(card: .previewRead("specs/roadmap.md", """
            # AgentClinic roadmap

            Four ordered phases. See `AGENTS.md`.

            - `app.py` — the FastAPI application
            """))
        ToolCardView(card: .previewRead("pyproject.toml", """
            [project]
            name = "agentclinic"
            version = "0.1.0"
            dependencies = ["fastapi[standard]==0.115.10"]
            """))
    }
    .padding()
    // Tall enough for all three: a shorter window squeezed each card to its
    // first line.
    .frame(width: 520, height: 720, alignment: .top)
}

// SU.18, D2: a `run` that fell back to bash, as exit 0, exit 1 and the limit.
#Preview("bash runs") {
    VStack(spacing: 8) {
        ToolCardView(card: .previewBash("[exit 0 in 2.3 s]\nBuild complete!\n5 passed"))
        ToolCardView(card: .previewBash("[exit 1 in 0.4 s]\nerror: no such module 'Foo'"))
        ToolCardView(card: .previewBash("[stopped after 120 s, the time limit]\nCompiling…"))
    }
    .padding()
    .frame(width: 520, height: 460, alignment: .top)
}

// EN.2, D5: `git` colored as a diff; `test` with pytest's line in its metadata.
#Preview("git and test") {
    VStack(spacing: 8) {
        ToolCardView(card: .previewGit)
        ToolCardView(card: .previewTest)
    }
    .padding()
    .frame(width: 520, height: 420, alignment: .top)
}
