# SU.16 plan: files as links

[Spec](../specs/2026-10-18-su16-files-as-links-design.md), accepted by the
owner on 2026-10-18 with its defaults: a bare name links when unique (D2),
and prose paths don't link (D4). The branch is `su16-file-links`. No GPU.

## Decisions

The spec's D1–D9.

## Tasks

1. **Kit: `FileLink`** (D1, D2, D8), in `Sources/SwiftStarKit/FileLink.swift`.
   - `struct FileLink: Equatable, Sendable { path, url, isEngineCopy }`
   - `struct FileLinkResolver: Sendable`, built from `source`, `worktree`,
     `known` and `exists`. Its `func resolve(_ text: String) -> FileLink?`
     resolves a path.
   - `FileLink.destination(_ path:)` and `FileLink.path(fromDestination:)`
     convert between a path and its `swiftstar-file:` link destination.

   Tests in `FileLinkTests`, over a resolver whose disk is a set:
   - `normalizes`: `./a.swift`, `a.swift:12:3`, and an absolute path under
     the source or the worktree
   - `bareNameLinksWhenUnique`: a duplicate name doesn't link
   - `worktreeCopyWins`: and the checkout's copy opens when the worktree is
     missing
   - `newFileInWorktreeLinks`
   - `outsideTheRootsDoesNotLink`
   - `destinationRoundTrips`: including a path with spaces
2. **Kit: Markdown links** (D7).
   `MarkdownPreprocess.fileLinks(_:resolve:)` rewrites whole inline code
   spans. It leaves alone fences, indented code, prose, and spans already
   in a link.

   Tests in `MarkdownPreprocessTests`:
   - `spanBecomesALink`
   - `codeBlockAndProseStayPlain`
   - `spanInsideALinkStays`
   - `tableCellSpanLinks`
   - `spacedPathIsEncoded`
3. **Engine and controller: the worktree** (D3, D9).
   - `ReceiptReader.worktree(sessionDirectory:) -> URL?`, in
     `Sources/SwiftStarEngine`, reads `receipt.json`'s `worktree_path`.
   - `EngineController` re-reads it at each pause. It clears it on start and
     exit, and keeps `fileLinks: FileLinkResolver?` with a cache that clears
     when its inputs change.

   Tests:
   - `ReceiptReaderTests`: the worktree from both fixture receipts, nil
     when the directory is missing, nil without a receipt
4. **UI** (D4–D7).
   - `TranscriptView` hosts one `.quickLookPreview`. It hands rows a
     `FileLinkAction`, through the environment, that resolves and opens.
   - `ToolCardView` loses its own binding. Its header uses link styling.
   - `MentionsLine` gets one link per attached name.
   - `MarkdownText(_:links:)` sets `linkHandler` before
     `setMarkdownManually`. It opens `swiftstar-file:` links through Quick
     Look and web links in the browser.
   - Answers and narration opt in.

   Checks:
   - Previews rendered, with `source` set to this repository.
   - The gallery: a click on a header, an attachment and an answer's span
     opens Quick Look. The click is posted with a CGEvent, and the panel is
     checked with System Events.
5. **Docs.** ROADMAP, CHANGELOG and both tiers.

## Result

Done 2026-10-18, with no GPU.

- **Commits:**
  - `8c708c4`: Task 1
  - `ddc97f5`: Task 2
  - `39d5520`: Task 3
  - `65d9e05`: Task 4
  - this close
- **Tests:**
  - `just test` (210) and `just integration` (90) pass.
  - Every new Kit, Engine and controller behavior was broken, and its test
    failed. Two cases got their tests fixed along the way:
    - The `..` guard's test first missed: its fake disk didn't resolve
      `..` the way a real one does.
    - The one-space rule had no test, so it got one.
- **The spec's risk was real, and it was two bugs.** A click on an answer's
  link did nothing in the gallery. The debugger found why:
  - **The fork's AppKit `MarkdownTextView` never makes itself its label's
    delegate** (its UIKit init does, `MarkdownTextView.swift:44`). So
    Litext found the link under the click and told no one, and no link in
    an answer had ever worked on macOS. `MarkdownNSText` now sets
    `view.textView.delegate = view`.
  - **The label makes itself first responder on the click,** and Quick
    Look finds its controller through the responder chain, where the label
    isn't. The open now waits until the window lets go of it. Without that,
    the panel never showed (checked twice).

  With both, a click on `SessionView.swift` in the gallery's answer opens
  Quick Look in about 2 s. The header's link opened it too. Attachments use
  the same button as the header. These clicks were posted as mouse events,
  and the panel was found by its window.
- **Not covered by a test:** both Markdown fixes are AppKit wiring, checked
  only in the gallery. A future fork bump should repeat that click.
- **Diverged:**
  - **Links are the system link blue everywhere.** The fork's default link
    color is orange, so the theme's `highlight` (used only by links) is now
    `.linkColor`.
  - **`EngineToolCard.fileURL(source:)` and its tests went,** since nothing
    called them. One behavior changed: an absolute path outside the
    repository (`/etc/hosts`) no longer opens (D1). The trailing-slash case
    moved to `FileLinkTests`.
  - **The gallery's answer** names `SessionView.swift`, not `SessionView`,
    so it has a file to link.
  - **`fileLinks` controller tests** check that the engine's copy no longer
    opens after the session ends. They don't check that the checkout's copy
    does, since this test's checkout may lack the file.
- **Previews:** these were rendered and looked at:
  - ToolCardView's "Link header"
  - TranscriptRowView's "Mentions" and "Answer with file links": a plain
    `missing.swift`, a linked `:42` path and a linked table cell

