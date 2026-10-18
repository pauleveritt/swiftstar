# SwiftStar SU.16 design: files as links

Date: 2026-10-18. Status: **written, awaiting the owner's acceptance.**

## Goal

Every place the transcript names a file opens it in Quick Look, and looks
like it can be clicked:
- tool card headers
- `@` attachments
- file paths in the model's answers

While a session runs, a file the engine edited opens as the engine's copy,
in its candidate worktree, not as the checkout's.

Out of scope:
- the Changed-files-after-each-turn backlog item
- diffs
- paths in prose outside backticks
- opening files in an editor

No engine change and no GPU: tests run over fixtures and the fake engine.

## What exists (cited at `main` `48c354f`)

- **Tool card headers.** Only a `read`, `edit` or `write` card with a
  resolvable path gets a header button, and it's `.plain`. Nothing marks
  it as clickable (`ToolCardView.swift:60-79`).
  - The button sets a per-card `.quickLookPreview` binding (`:15`, `:55`).
  - The card checks the disk on every render (`:83-86`).
  - `EngineToolCard.fileURL(source:)` resolves against the checkout only
    (`EngineTranscript.swift:67-73`).
- **`@` attachments** are one joined, secondary label, with no links
  (`TranscriptRowView.swift:85-108`).
- **Markdown links** already render in the link color with a pointing
  hand. But SwiftStar never sets the renderer's `linkHandler`
  (`MarkdownTextView.swift:100`), so a click does nothing. Nothing turns a
  path into a link.
- **`receipt.json`'s `worktree_path`** is never read. The engine writes it
  at every pause (`session_receipt.py:175`) and removes the worktree when
  the session ends (`candidate.py:143-177`).
- **`EngineController.workspaceFiles`** is the checkout's tracked files
  (`git ls-files`, filtered, at most 20,000; `WorkspaceFileLister.swift:7-21`).

## Decisions

- **D1. One resolver, in Kit.**
  - **Signature:** `FileLink.resolve(_ text: String, source: URL?,
    worktree: URL?, known: Set<String>, exists: (URL) -> Bool) -> FileLink?`.
    It returns the relative path, the URL to open, and which copy that is.
  - **Normalizing:** it drops a leading `./` and a trailing `:line` or
    `:line:col`, and turns an absolute path under `source` or `worktree`
    into a relative one.
  - **Which copy:** the worktree's when the worktree exists and holds the
    file. Otherwise the checkout's, when it holds the file.
  - **Pure:** the disk check is passed in, so the Kit tests use none.
- **D2. A bare file name links when it's unique.** `` `Severity.swift` ``
  links to `Sources/SwiftStarKit/Severity.swift` when exactly one known
  path ends with `/Severity.swift`. Two matches make no link. The model
  often names files this way; guessing between two would open the wrong one.
- **D3. The worktree comes from `receipt.json`.**
  - **When:** an Engine-side `ReceiptReader` reads `worktree_path` once the
    session directory is known, at the first pause, and again at each later
    pause.
  - **When it's gone:** a missing receipt, a missing key or a missing
    directory leaves `worktree` nil, so everything opens the checkout's copy.
  - **After the session ends:** the engine removes the worktree, so the
    checkout's copy is what opens. The link's help says which copy:
    "Quick Look Severity.swift (the engine's copy)".
- **D4. Which paths link.**
  - **Tool cards:** `read`, `edit` and `write`, as today. `grep` and `ls`
    paths can be directories, and Quick Look shows little for those.
  - **`@` attachments:** each attached name becomes its own link. A missing
    name stays plain red text.
  - **Answers and narration:** an inline code span whose whole text
    resolves (D1, D2). Code blocks, prose, spans already inside a link, the
    report card and thinking never link.
- **D5. What a link looks like.** The link color, the pointing hand on
  hover, and a "Quick Look …" help tag. A tool card header keeps its icon
  and weight and takes the link color.
- **D6. One Quick Look per window.** The cards' own bindings go. A
  `FileLink` opens through one `.quickLookPreview` on the transcript, set
  through the environment, so cards, attachments and Markdown share one
  path. Space in Quick Look keeps working as it does today.
- **D7. Markdown links are made before parsing.**
  - `MarkdownPreprocess.fileLinks(_:resolve:)` rewrites a matching span
    `` `p` `` to `` [`p`](swiftstar-file:<percent-encoded p>) ``.
  - It reuses the `deLaTeXed` machinery: code-span runs, plus the fences,
    lists and quotes it already tracks.
  - `MarkdownText` gains an opt-in `fileLinks` closure. It's set only for
    answers and narration.
  - Its `linkHandler` is set before `setMarkdownManually`, so links in
    tables work too (`TextBuilder+Do.swift:190`).
  - A `swiftstar-file:` click opens Quick Look. An `http(s)` click opens
    the browser, which today does nothing at all.
- **D8. Files the engine created.** A file the engine made exists only in
  the worktree and isn't in `known`. D1 also looks in the worktree when it
  exists, so a new file links while its session runs.
- **D9. No disk check per render.** Resolved links are cached by path. The
  cache clears when `worktree` changes, the session ends or `workspaceFiles`
  reloads.

## Testing

- **Fast tier (Kit):**
  - **`FileLink`:**
    - relative, absolute, `./` and `:line` forms
    - a unique and a duplicate bare name
    - worktree over checkout
    - a missing worktree, and a file only in the worktree
  - **`MarkdownPreprocess.fileLinks`:**
    - a span becomes a link
    - a code block, prose and a span already in a link don't
    - a path with a space is encoded
    - a table cell's span links
  - **The attachments row's items:** one per name, and missing ones plain.
  - Each test is shown to fail with its behavior broken.
- **Integration:** `ReceiptReader` over `fixtures/sessions/*/receipt.json`,
  a temp directory standing in for the worktree. Then the controller's
  `worktree` after a fake-engine pause whose capture path points at a copy
  of that session directory.
- **Previews,** rendered with `RenderPreview`, with `source` set to this
  repository so the files exist:
  - tool cards with a link header
  - the attachments row
  - an answer with a linked span and a duplicate bare name that doesn't link
- **By hand:** Quick Look opening is a click, which `RenderPreview` can't
  show. That check is for the gallery, or the owner.

## Done when

- D1–D9 are built and both tiers are green.
- The previews have been looked at.
- A click on each kind of link opens Quick Look in the gallery.
- ROADMAP and CHANGELOG are updated.

## Risks

- **A wrong guess opens the wrong file.** D2 links a bare name only when
  it's unique, and D1 only when the file exists.
- **The fork's link click works at the AppKit level.** If it doesn't reach
  `linkHandler` inside a `ScrollView` cell, D7 needs a patch in
  `pauleveritt/MarkdownView`. The first task proves the click before
  anything builds on it.
- **Rewriting changes the Markdown that's cached,** so a `workspaceFiles`
  reload re-parses each visible answer once. That's acceptable at today's
  sizes.
