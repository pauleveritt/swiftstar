# SwiftStar SU.5 design: cleanup and test modernisation

**Date:** 2026-10-04
**Status:** accepted 2026-10-13. All four decisions (§2) accepted as
recommended — ready to plan.
**Phase:** SU, cycle SU.5
**Source:** ROADMAP.md's SU.5 row, scoped from the
[repo audit](../research/2026-10-04-repo-audit.md) (taken at `fb46abb`). Each
item below was re-checked against `main` at `e390796`, after SU.4 moved files.
**Written by:** Xcode 27's Claude Agent (Opus 5.5). Run inside the SU.4 loop:
the `ui-loop` skill applies to every view change.

## Goal

Leave the code and docs saying only true things, and move the logic SU.4's
split exposed out of views and under test. Concretely:

1. Delete code nothing uses, and fix comments and docs that describe code
   that no longer exists.
2. Fold duplicated constants and helpers into one place each.
3. Fix the Quick Look path bug.
4. Move the label and button logic out of the session views into Kit, with
   tests.
5. Use current Swift Testing features where tests are new or touched.
6. Reorganise `ROADMAP.md` so "what's next" is quick to find.

## 1. What changed since the audit

- **Font size (audit §1e) is mostly fixed.** SU.4 moved the reads below the
  modifier. What's left is a dead `.font` on the toolbar menus, which ignore
  it: a 30 pt probe rendered unchanged.
- **`SessionView`'s logic (audit §1f) now sits in four small views.** The
  menu labels are in `SessionToolbar`, the status text in `StatusBarView`,
  and the send/stop state and notice in `ComposerView`. That makes the
  extraction a set of small, separate moves.
- **The Quick Look bug can't be fixed the way the audit hoped.** The
  engine's `session` event reports `source`, the git root it works from. It
  doesn't report the candidate worktree it edits in, and it deletes that
  worktree when the session ends (`ds4-engine/src/ds4_engine/sessions.py:1-9`,
  and a recorded fixture's `session` event). So SwiftStar can open the
  checkout's copy, but not the edited one.

## 2. Decisions

The owner was asked these on 2026-10-04 and accepted all four as recommended
on 2026-10-13.

**D1. How SU.5 is cut.** *Accepted: two plans, run in order.* Plan **5a**
covers code and tests (§3.1–§3.6). Plan **5b** is docs only: the ROADMAP
reorganisation and the stale docs (§3.7). The work is too large for one plan
under the 400-line ceiling, and the docs half carries different risks.

**D2. How far Swift Testing goes.** *Accepted: targeted.* New tests use
current features. Existing tests change only where they're duplicated or
already being edited. There is no sweep of all 16 files.

**D3. What Quick Look opens.** *Accepted: the checkout's copy, resolved
against the engine-reported `source`.* That fixes the miss when the picked
folder is a subfolder. Showing the edited copy needs the engine to report
its candidate worktree, so it goes in the Backlog's "Engine requests". The
first proposal, "the engine's edited copy", is withdrawn: §1 shows the wire
doesn't carry it.

**D4. What's excluded.** *Accepted: all four of these stay out of SU.5.*
- The old "agent" copy in the UI, such as "Ask the agent…" and the "Agent"
  title. It's a UI-copy change for SU.6.
- Catalog fields decoded but never read. `provenance.md` keeps them on
  purpose.
- Python and the Sphinx docs site. They're tied to the parked P14 and get a
  Backlog entry.
- `#if DEBUG` around the preview fixtures and the Markdown self-test. It's a
  judgement call with no defect behind it.

## 3. Design

### 3.1 Dead code (plan 5a)

Each deletion is grep-verified at the time of the task, and the tests that
exist only to cover dead code go with it.

- `EngineTranscript.isAwaitingInput` and `EngineTranscript.canStop`: written
  but never read in `Sources/`. P32 already named `isAwaitingInput` for
  deletion.
- `EngineController.sessionDirectory`: nothing reads it.
- `DefaultsKey`'s `CaseIterable` conformance.
- The executable target's `resources:` entry, if the icon reaches the app
  bundle without it. `Tools/make-app.sh` copies the `.icns` directly, so
  today it ships twice. Check by building the app.
- `MarkdownText`'s `public`, if nothing outside the module needs it.
- The toolbar menus' `.font`, which has no effect (§1).
- **Kept:** `EngineTranscript.isQueued(rowAt:)` and `queuedUserRows`. They
  hold the engine-confirmed queue state from P29.3, which the UI doesn't
  show yet. Showing "Queued" only for confirmed rows is a UI change, logged
  for SU.6.

### 3.2 Stale comments (plan 5a)

Fix in place: the comment about a missing "P32 Backlog" entry in
`EngineSession`, the `PathAbbreviation` doc, `MarkdownText`'s "coalesces
deltas", `MarkdownPreprocess`'s "`think` events", and the pre-P28 framing in
`ProjectRoot`. Drop the provenance-only comments (audit §1c), but keep
`EngineSession`'s comment on why it doesn't use `FileHandle.bytes`.

### 3.3 Duplication (plan 5a)

- `EngineController` resolves the executable in two places. `start()` uses
  `resolveExecutablePath()` too, but keeps its not-found branch, which needs
  the list of places searched.
- The grace periods, the 4 KiB stderr limit and the `"Session artifacts:"`
  marker each get one definition, in Kit or Engine.
- One trim helper replaces three.
- GiB and number formatting moves into `MetricsFormatting`, with one locale
  policy: the user's locale for display, except where a test pins the
  output. The forced `en_US` in `EngineModelCatalog` is the case to decide.

### 3.4 Smells (plan 5a)

- `EngineController.defaultsObserver` is never removed, and it fires on the
  controller's own writes. It gets removed on deinit, and the controller
  ignores its own writes.
- `SettingsView`'s slider derives its range from
  `TranscriptFontScale.sizes`. The force unwrap goes.
- `MarkdownNSText` builds its theme once per update instead of twice.

### 3.5 The Quick Look bug (plan 5a)

`EngineSessionInfo` gains `source: URL?`, decoded from the `session` event.
`ToolCardView` resolves relative tool paths against it, and falls back to
the picked workspace only before a session reports it. A parser test pins
the decode, and a Kit function, `EngineToolCard.fileURL(source:)`, pins the
resolution. That function moves out of the view as part of §3.6.

### 3.6 View logic into Kit, with tests (plan 5a)

Each piece moves to a Kit type next to its siblings. The view calls it, and
a fast-tier test pins it. Every new test is shown to fail when its behaviour
is broken.

| Logic, now in | Moves to |
|---|---|
| model and context menu labels, including the "loaded → chosen" form (`SessionToolbar`) | `ModelMenu.label(...)`, `ContextMenu.label(...)` |
| status-bar text (`StatusBarView`) | `MetricsFormatting.statusLine(phase:label:metrics:)` |
| send/stop button state (`ComposerView`) | `EngineComposer.button(forInput:)` returning `.send(enabled:)` or `.stop` |
| not-found notice (`ComposerView`) | `EngineSessionPhase.notFoundNotice` |
| custom context entry parsing (`SessionView`) | `ContextMenu.parseCustom(_:)` |
| slider slot mapping (`SettingsView`) | `TranscriptFontScale.slot(for:)`, `.size(forSlot:)` |
| tool-card file URL (`ToolCardView`) | `EngineToolCard.fileURL(source:)` (§3.5) |

Two `EngineController` behaviours get tests here, because §3.3 and §3.4 edit
the controller. That meets the reopen condition in SU.3's Backlog entry:
- a fixture controller's `start()` leaves it `.idle`;
- its own defaults writes don't trigger a catalog reload.

Each view whose logic moves has its previews re-rendered and looked at.

### 3.7 Docs and ROADMAP (plan 5b)

- **Stale docs.** `BRIEF.md` and `docs/sdd.md` describe a `FastTierGuard`
  tripwire that "fails the build"; it is now a grep in `just test`.
  `sdd.md` says "two easiest to forget" above three bullets. Both docs and
  the `Justfile` claim CI that doesn't exist. Also fix the glossary's
  `AgentToolCardView`, README's "build and launch", `pyproject.toml`'s
  "Python … for documentation and nothing else", and `docs/index.md`'s P14
  line.
- **ROADMAP.**
  - Give the SU rows a real table header and make `just lint-docs` check
    them. Its pattern is `^\| P[0-9]` today.
  - Move closed history into a linked archive doc: the P0–P32 table, the
    P29 steps, and the Backlog groups closed by P28.
  - Fix the stale rows the audit listed (§4): the missing P25/P26 rows, the
    resolved "P29.10's deferred minors" entry, and P18's opening line.
  - Keep `## Now` as a pointer.
- **Plans.** Move the pre-P28 plans still sitting in the current plans
  directory into `archive/`: P12, eval-cli 1a–1c, and P24.

## 4. Done when

- Every §3.1 item is deleted or kept with its reason, and grep finds no
  caller of a deleted symbol.
- §3.6's seven moves are made, each with a fast-tier test shown to fail.
  The two `EngineController` tests exist.
- Quick Look resolves against the engine's `source`. The Backlog has an
  engine request for reporting the candidate worktree.
- Every touched preview has been rendered and looked at. Both test tiers
  pass and the build has zero warnings.
- Plan 5b: the SU rows are linted, the closed history is archived and
  linked, the stale docs are fixed, and `just lint-docs` passes.
- The ROADMAP SU.5 row and `## Now` are updated, and SU.6 gains the
  "confirmed Queued" item.

## 5. Risks

- **Formatting changes can move test expectations.** The locale policy
  (§3.3) is decided per call site, and a test that pins `en_US` output
  stays pinned.
- **Removing `resources:` could drop the icon.** Build the app and check
  before deleting it.
- **Moving closed history out of ROADMAP breaks links into it.** Grep the
  repo for anchors into ROADMAP before moving anything.

## Revision, 2026-10-13

Made in the re-plan after ds4-engine `5451cd7d`. Evidence:
[`2026-10-13-engine-catch-up-and-repo-audit.md`](../research/2026-10-13-engine-catch-up-and-repo-audit.md)
(cited below as "the audit"). The text above stands as written; this
section supersedes it where they differ.

- **Order.** EN.1, the engine catch-up, runs before SU.5. Two exceptions:
  the B1 and B4 fixes can go first if wanted, since neither depends on
  EN.1.
- **D1 re-cut.** The docs half (§3.7) was done by the re-plan itself: the
  ROADMAP reshape, the pre-P28 docs removed behind the `docs-before-slim`
  tag, and the stale docs fixed. Plan **5a** is now code (§3.1–§3.6 plus
  the audit §2). Plan **5b** is tests (the audit §3). Either splits further
  if the 400-line cap needs it.
- **D2 superseded.** On the owner's request (2026-10-13), the test
  consolidation is a sweep, not targeted: about 143 to 66 fast-tier
  functions through `@Test(arguments:)`, plus shared `Fixtures.swift` and
  integration `Support.swift`. Cutting the four fake-only tests stays an
  owner call at plan time.
- **§3.5 corrected.** Quick Look must not store `source` in
  `EngineSessionInfo`, because `EngineTranscript.session` is cleared when a
  session ends. Keep the `--source` the controller already resolves, past
  the session's end, and resolve with `appending(path:)`. No parser change.
- **§3.1 corrected.**
  - `EngineSessionModel.sessionDirectory` goes with the controller's.
  - `canStop`'s tests move to `isBusy`.
  - Dropping `resources:` needs `exclude:`.
  - `MarkdownText`'s `public` goes only after the unused self-test is
    deleted or wired into `make-app`.
- **§3.4 corrected.** The defaults observer returns early when the
  executable string is unchanged; ignoring only the controller's own writes
  is not enough.
- **Added to 5a:**
  - the audit's bugs B1, B3, B4 and B6–B9
  - its dead code and fossils
  - the idioms it lists: `@Entry`, a single `SIGPIPE` setup, file splits
- **Moved to SU.6:** the catalog's never-sent fields and the decoding of
  `plan_gib` and `size_bytes`.
- **Done when (added):** each audit bug has a test shown to fail before its
  fix, or a recorded reason it can't have one.
