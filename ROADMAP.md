# Roadmap

> **Planning surface, not the front door.** What's in flight, what's next,
> and the Backlog. Start with [`README.md`](README.md); the settled design is
> [`BRIEF.md`](BRIEF.md), how work runs is [`docs/sdd.md`](docs/sdd.md), and
> closed history is [`docs/history.md`](docs/history.md).

## Now

- **Next:** the owner's live checks of SU.6f-SU.11 in the app (prompt history, ⌘+/⌘−, the fade, a new conversation's row, the rate tooltip) and of SU.7b's menus and alert; then the punch list's last item, engine information worth showing (not brainstormed).
- **Next in AN:** [AN.3](#phase-an-analyze), remedies (not brainstormed); the owner's app click-through of AN.2 is open.
- **Blocked on the engine:** showing the edited copy of a file (the candidate
  worktree), and more than one window.

## Phase EN: the engine contract

One cycle per ds4-engine landing that SwiftStar catches up to.

| # | Cycle | Direction | Status |
|---|---|---|---|
| EN.1 | Catch up to `5451cd7d` | Drop a saved model the engine no longer offers; show `tool_rejected` as a declined card; honour `relaunch` for `/model`, `/rewind` and `/resume`; dedupe narration and answer if they repeat; fix `just capture` and re-record on the 27B | done 2026-10-13: live on the 27B, the stale model, `/rewind 1` and a model switch worked through the controller (no window clicks). [spec](docs/superpowers/specs/2026-10-13-en1-engine-catch-up-design.md), [plan and Result](docs/superpowers/plans/2026-10-13-en1-engine-catch-up.md) |

## Phase AN: Analyze

Learn which session telemetry matters by reading it, then move what proved
useful into ds4-engine. [Spec](docs/superpowers/specs/2026-10-13-an-session-analysis-design.md).

| # | Cycle | Direction | Status |
|---|---|---|---|
| AN.1 | The report | `just last` and `/last`: the newest session's failed and useless steps, time, per-pause rates and raw signals, from the session directory with no model call | done 2026-10-13: [plan and Result](docs/superpowers/plans/2026-10-13-an1-session-report.md) |
| AN.2 | Analyze and Done | Analyze on the last answer resumes the session as a fork, shows the report and asks about it there; Done resumes the original, so the main context returns as it was | done 2026-10-13: live, fork 3 s and Done 2.9 s, twice. [Plan and Result](docs/superpowers/plans/2026-10-13-an2-fork-and-return.md); the `/rewind` attempt [stopped](docs/superpowers/plans/2026-10-13-an2-analyze-and-done.md#result) |
| AN.3 | Remedies | Suggest and apply fixes from the flags, applied after Done in the main session | not brainstormed |
| AN.4 | Into ds4-engine | `ds4-dogfood last [--session] [--json]` takes the script, tests and fixture; the app's `reportArgv` switches to it | opens on the owner's call, once the flag rules and summary rows stop changing |

AN follow-ups, from AN.2's Result and final review, for the next AN cycle:
- **The report follows `resumed_from`.** After one Analyze and Done, the
  main session is a new directory, and a second Analyze reported "no flagged
  steps" for a session whose earlier turns had one (live, 2026-10-13).
- **A resumed-then-answered fixture,** so Done's return can be tested over
  the fake engine.

## Phase SU: SwiftUI

| # | Cycle | Direction | Status |
|---|---|---|---|
| SU.1 | SwiftUI modernisation | `@Environment` controller, `.onSubmit` composer, `.defaultScrollAnchor` transcript, closing the last window quits | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su1-swiftui-modernisation-design.md), [plan](docs/superpowers/plans/2026-10-03-su1-swiftui-modernisation.md) |
| SU.2 | Testable view logic | Move view-adjacent logic into Kit, with tests | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su2-testable-view-logic-design.md), [plan](docs/superpowers/plans/2026-10-03-su2-testable-view-logic.md) |
| SU.3 | Preview adoption | A fixture-backed `#Preview` on every view | done 2026-10-04: views moved to the `SwiftStarUI` library so Xcode can preview them. [spec](docs/superpowers/specs/2026-10-03-su3-preview-adoption-design.md), [plan](docs/superpowers/plans/2026-10-03-su3-preview-adoption.md) |
| SU.4 | Xcode-first UI loop | Xcode 27 and its agent as the place UI work happens: feature folders, previewable parts, `RenderPreview` before a UI change is done | done 2026-10-04: [spec](docs/superpowers/specs/2026-10-04-su4-xcode-first-ui-loop-design.md), [plan](docs/superpowers/plans/2026-10-04-su4-xcode-first-ui-loop.md), [handoff](docs/superpowers/research/2026-10-04-su4-handoff-brief.md) |
| SU.5 | Cleanup and test consolidation | Remove dead code, fossils and the audit's bugs; move view logic into Kit; fold tests into tables with shared support | done 2026-10-13: 230 tests → 130; integration 13–19 s, from ~29. [5a1](docs/superpowers/plans/2026-10-13-su5a1-bugs-and-plumbing.md), [5a2](docs/superpowers/plans/2026-10-13-su5a2-kit-moves-and-tidy.md), [5b](docs/superpowers/plans/2026-10-13-su5b-test-consolidation.md), each with its Result. [Spec](docs/superpowers/specs/2026-10-04-su5-cleanup-and-test-modernisation-design.md) as revised |
| SU.6 | UI tweaks | A punch list of small UI fixes and engine information worth showing (below) | 6a–6f done 2026-10-13, 6g 2026-10-14, each with its plan and Result: `docs/superpowers/plans/*-su6*.md`. One item left, below |
| SU.7 | Project focus, switching and resume | The project as the window's identity; its past sessions in the sidebar, resumable; quick, deliberate switching between projects | 7a and 7b done 2026-10-13: this project's conversations in a sidebar; switching asks first mid-turn; the Recent menus (toolbar, Open Recent, Dock) resume a project's newest conversation. Plans: [7a](docs/superpowers/plans/2026-10-13-su7a-sessions-and-resume.md), [7b](docs/superpowers/plans/2026-10-13-su7b-switching-projects.md). 7c (windows) waits on the engine |
| SU.8 | Prompt history | ↑/↓ in the composer steps through earlier prompts | done 2026-10-13: this conversation's typed prompts, while the field is empty or unedited. [Plan and Result](docs/superpowers/plans/2026-10-13-su8-prompt-history.md) |
| SU.9 | Font size | One setting scales every text in the window: 5 sizes, the middle the default; ⌘+ and ⌘− after 7b lands | done 2026-10-13: 14–24 pt, 18 the default, under a new key; the shortcuts wait in the punch list. [Plan and Result](docs/superpowers/plans/2026-10-13-su9-font-size.md) |
| SU.10 | Status bar rates | The two token rates as steady numbers, explained by a tooltip | done 2026-10-14: prefill / generation as bare numbers in fixed slots; the tooltip names them as session averages. [Plan and Result](docs/superpowers/plans/2026-10-14-su10-status-rates.md) |
| SU.11 | The conversation first | Toolbar menus with icons, the window titled and the list selected by the conversation, New Conversation in the list, even inspector type | done 2026-10-14, checked in the gallery: icons in every menu, the window titled by the conversation, its row listed and selected, New Conversation first in the list. [Plan and Result](docs/superpowers/plans/2026-10-14-su11-conversation-first.md) |
| SU.12 | The gallery app | The real window and menus over fixtures, no engine, for checking toolbars and menus by screenshot | done 2026-10-14: `SwiftStarGallery` and `Tools/window-shot.sh`; the agent captures the real window. [Plan and Result](docs/superpowers/plans/2026-10-14-su12-gallery.md) |
| SU.13 | Two leftovers | The memory widget's crash check, in a gallery Debug run (SU.3's leftover); the report card's wide tables at narrow widths (from AN.2) | done 2026-10-14: no crash in 41 flips; wide tables scroll with a scroller, via `pauleveritt/MarkdownView`. [Plan and Result](docs/superpowers/plans/2026-10-14-su13-two-leftovers.md) |
| SU.14 | The `@` file picker | Typing `@` in the composer offers the workspace's files; choosing one inserts `@path`, which the engine expands; the `mentions` event shows what was attached | done 2026-10-14: `@` offers the workspace's files as the TUI ranks them; the engine attaches; an attached/missing line under the prompt; the owner tried it. [Plan and Result](docs/superpowers/plans/2026-10-14-su14-file-picker.md) |
| SU.15 | Colored code in tool cards | A tool card's result preview colored by its file's language, with the highlighter answers' code blocks already use; Markdown as colored raw text | done 2026-10-14: a card's result colored by its file's language, light and dark; Markdown as colored raw text. [Plan and Result](docs/superpowers/plans/2026-10-14-su15-colored-code.md) |
| SU.16 | Files as links | Every file reference opens Quick Look and looks like a link: tool card headers (today a plain button), `@` attachments, paths in answers that name a real file; engine-worktree files wait on the engine | not brainstormed |

### SU.6 punch list

- **Engine information worth showing** (held back from SU.6g; needs a look
  at what the engine sends):
  - start-up timings: `candidate_ready`, `index_primed`
  - the engine's stderr start notices
  - model sizes from `plan_gib` and `size_bytes`; drop the catalog fields
    the engine never sends

## Backlog

Deferred, each with the condition that reopens it.

### Front-end

- **An Apply button.** Applying stays a terminal step:
  `ds4-dogfood apply <id>`. *Reopens if copying that command becomes daily
  friction and the engine offers a machine-readable apply.*
- **Token streaming.** The engine's seam is the pause, never a per-token
  callback. *Reopens only if ds4-engine changes that.*
- **Packaging ds4-engine inside the `.app`.** Today the user installs it
  with `uv tool install`. *Reopens when someone other than the author needs
  to run the app without a terminal.*
- **A shell toggle.** Tool policy is the engine's. *Reopens if ds4-engine
  adds a spawn-time tool-policy flag worth a Settings control.*
- **The catalog loader's pid-reuse window.** There is a small window before
  SIGKILL in which the pid could be reused. *Reopens if seen live.*

### Engine requests

Things SwiftStar can't show or do until ds4-engine changes. Raise them
there.

- **The `session` event doesn't report the candidate worktree.** So Quick
  Look opens the checkout's copy, not the edited one.
- **`models --json` sends no `default_model_id`.** So "Engine default"
  can't name the model it means.
- **`prefill_tokens` isn't prefill.** It's the transcript length minus evals
  (`operator_telemetry.py:101-113`), so tokens the engine didn't prefill
  count as prefilled:
  - A prefix-cache hit's tokens. Since SU.6b, SwiftStar leaves those out.
  - A resumed conversation's loaded KV. Session `160812` read about 106,700
    tok/s.
  - After `/clear` or a compaction, the count collapses.
- **A `files --json` command,** for SU.14's picker. Not needed: the engine
  expands `@path` in NDJSON prompts itself (`mentions.py`), so SwiftStar can
  list files with `git ls-files` (checked at `5451cd7d`, 2026-10-14).
- **A second `/rewind` in a rewound session goes wrong** (live, 2026-10-13,
  sessions `20261013-121126` and `-121133`). In a session resumed with
  `--rewind-to 1` (one turn), `/rewind 1` was refused with `--rewind-to 0`
  ("after prompt 0"). The relaunch then resumed two turns, one of them the
  turn the first rewind removed, and dropped the newest. SwiftStar showed
  exactly what the engine sent. Seen with the `/rewind` queued behind a busy
  turn. **Seen again unqueued** (AN.2 gate 1, sessions `20261013-153218`
  and `-153456`, suffix `-session-last`): `rewound_to 0`, and the resumed
  turns included a prompt the first rewind had removed. It stopped AN.2's
  first attempt; the second avoids `/rewind`. Filed as [ds4-engine#219](https://github.com/pauleveritt/ds4-engine/issues/219).
- **`resumed.turns` carries no narration.** So a 27B turn rebuilt after a
  rewind or resume shows only its one-line summary, not the full reply
  (SU.6a).
- **Watch, not a request: the Satyrn rename.** `ds4-dogfood` and the
  `~/.local/state/ds4-engine` paths may be renamed. SwiftStar would need to
  change `EngineCommand.executableName`, and probing both names is the
  likely fix.

Closed 2026-10-13: both were already answered upstream before 2026-10-04,
found by the [audit §1](docs/superpowers/research/2026-10-13-engine-catch-up-and-repo-audit.md).
- **Rejected tool calls emit no event:** they do, as `tool_rejected`
  (TUI.36).
- **`/resume`, `/model` and `/rewind` re-exec in place:** under `--ndjson`
  they are refused with a `relaunch` argv instead (TUI.34).

### Process

- **Integration runs in two worktrees at once interfere.** Both use the test
  runner's `UserDefaults` domain (seen in SU.6c, alongside `session-last`).
  *Reopens if parallel runs become routine. The fix is a per-run defaults
  suite, injected into `EngineController`.*
- **`exitReportedWhenGrandchildHoldsPipe` failed twice under load (SU.7b).**
  The exit wasn't seen within 5 s, against a 500 ms drain limit, in slow
  full runs. It passed alone and in later runs. *Reopens if it fails again:
  look at exit reporting under load, not the bound.*
- **SU.1's window-close-quits live check covered idle only, not mid-turn.**
  The `quit()` mid-turn path is unit-tested. *Reopens when the GPU is free
  for a live run.*

- **Swift 6.4 closure identities in tests.** A closure inside `#expect(...)`
  and a same-typed sibling in one enclosing closure can run each other's
  body (SU.5b), so test bodies stay at function level. *Reopens when a
  toolchain fixes it; worth a minimal report to swiftlang.*

### Declined

- **A menu-bar extra** (2026-08-21). *Reopens only on a direct request.*
- **A docs site, P14** (2026-10-13). Markdown in the repository is the
  reader surface.
- **A native Markdown renderer** (2026-10-13, [SU.6d](docs/superpowers/plans/2026-10-13-su6d-markdown-renderer.md)).
  Every native option loses syntax colour, and a SwiftUI one also loses
  selection across an answer. *Reopens if the fork breaks on a toolchain
  bump, a crash traces to it, or a patch re-base is due.*

## History

Phase P (P0–P32), its steps and the Backlog it closed are in
[`docs/history.md`](docs/history.md).
