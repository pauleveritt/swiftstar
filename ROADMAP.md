# Roadmap

> **Planning surface, not the front door.** What's in flight, what's next,
> and the Backlog. Start with [`README.md`](README.md); the settled design is
> [`BRIEF.md`](BRIEF.md), how work runs is [`docs/sdd.md`](docs/sdd.md), and
> closed history is [`docs/history.md`](docs/history.md).

## Now

- **Next:** the rest of SU.6 (6d is done), then SU.7.
- **Blocked on the engine:** showing the edited copy of a file (the candidate
  worktree), and more than one window.

## Phase EN: the engine contract

One cycle per ds4-engine landing that SwiftStar catches up to.

| # | Cycle | Direction | Status |
|---|---|---|---|
| EN.1 | Catch up to `5451cd7d` | Drop a saved model the engine no longer offers; show `tool_rejected` as a declined card; honour `relaunch` for `/model`, `/rewind` and `/resume`; dedupe narration and answer if they repeat; fix `just capture` and re-record on the 27B | done 2026-10-13: live on the 27B, the stale model, `/rewind 1` and a model switch worked through the controller (no window clicks). [spec](docs/superpowers/specs/2026-10-13-en1-engine-catch-up-design.md), [plan and Result](docs/superpowers/plans/2026-10-13-en1-engine-catch-up.md) |

## Phase SU: SwiftUI

| # | Cycle | Direction | Status |
|---|---|---|---|
| SU.1 | SwiftUI modernisation | `@Environment` controller, `.onSubmit` composer, `.defaultScrollAnchor` transcript, closing the last window quits | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su1-swiftui-modernisation-design.md), [plan](docs/superpowers/plans/2026-10-03-su1-swiftui-modernisation.md) |
| SU.2 | Testable view logic | Move view-adjacent logic into Kit, with tests | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su2-testable-view-logic-design.md), [plan](docs/superpowers/plans/2026-10-03-su2-testable-view-logic.md) |
| SU.3 | Preview adoption | A fixture-backed `#Preview` on every view | done 2026-10-04: views moved to the `SwiftStarUI` library so Xcode can preview them. [spec](docs/superpowers/specs/2026-10-03-su3-preview-adoption-design.md), [plan](docs/superpowers/plans/2026-10-03-su3-preview-adoption.md) |
| SU.4 | Xcode-first UI loop | Xcode 27 and its agent as the place UI work happens: feature folders, previewable parts, `RenderPreview` before a UI change is done | done 2026-10-04: [spec](docs/superpowers/specs/2026-10-04-su4-xcode-first-ui-loop-design.md), [plan](docs/superpowers/plans/2026-10-04-su4-xcode-first-ui-loop.md), [handoff](docs/superpowers/research/2026-10-04-su4-handoff-brief.md) |
| SU.5 | Cleanup and test consolidation | Remove dead code, fossils and the audit's bugs; move view logic into Kit; fold tests into tables with shared support | done 2026-10-13: 230 tests → 130; integration 13–19 s, from ~29. [5a1](docs/superpowers/plans/2026-10-13-su5a1-bugs-and-plumbing.md), [5a2](docs/superpowers/plans/2026-10-13-su5a2-kit-moves-and-tidy.md), [5b](docs/superpowers/plans/2026-10-13-su5b-test-consolidation.md), each with its Result. [Spec](docs/superpowers/specs/2026-10-04-su5-cleanup-and-test-modernisation-design.md) as revised |
| SU.6 | UI tweaks | A punch list of small UI fixes and engine information worth showing (below) | in progress: [6d](docs/superpowers/plans/2026-10-13-su6d-markdown-renderer.md), [6a](docs/superpowers/plans/2026-10-13-su6a-what-you-read.md) and [6b](docs/superpowers/plans/2026-10-13-su6b-session-card.md) done 2026-10-13. Next: 6c (remembering) |
| SU.7 | Project focus, switching and resume | The project as the window's identity; its past sessions in the sidebar, resumable; quick, deliberate switching between projects | not brainstormed: [options](docs/superpowers/research/2026-10-04-project-focus-options.md). Resume works over `--ndjson` already ([audit §1](docs/superpowers/research/2026-10-13-engine-catch-up-and-repo-audit.md)); more than one window waits on the engine |

### SU.6 punch list

- **Metrics:** label Throughput's averages "session avg", since the engine's
  counters run over the whole process (SU.6b). Per-pause and per-prompt
  rates belong to phase AN's report.
- **Engine information worth showing:**
  - start-up timings: `candidate_ready`, `index_primed`
  - the engine's stderr start notices
  - model sizes from `plan_gib` and `size_bytes`; drop the catalog fields
    the engine never sends
- **Native look:** Liquid Glass affordances; `NativeTooltip` checked against
  plain `.help`.
- **Remembering:** the apply command kept across sessions; a first-launch
  workspace, and a saved workspace that no longer exists (seen 2026-10-13: it
  pointed at a deleted worktree, so every start was refused).
- **Left from SU.5a** (each plan's Result):
  - rate, duration, the status line and the ctx label ignore the locale; the
    inspector mixes GB and GiB
  - the model-list loader sleeps 1 s on every timeout, and waits out the
    whole timeout when a grandchild holds its pipe
  - the recorder can pair a new `resumed.ndjson` with an old
    `relaunch-rewind.ndjson`, and leaves a `.tmp` on an exception
  - `clamp`'s doc comment sits on `slot(for:)`; two comments still describe
    the toolbar font

## Backlog

Deferred, each with the condition that reopens it.

### Front-end

- **An Apply button.** Applying stays a terminal step:
  `ds4-dogfood apply <id>`. *Reopens if copying that command becomes daily
  friction and the engine offers a machine-readable apply.*
- **An `@` file picker.** The engine's picker lives only in its Textual
  presenter, and the wire has no file list. *Reopens when typing `@path` by
  hand becomes the friction. It needs an app-side listing or the engine
  request below.*
- **Token streaming.** The engine's seam is the pause, never a per-token
  callback. *Reopens only if ds4-engine changes that.*
- **Packaging ds4-engine inside the `.app`.** Today the user installs it
  with `uv tool install`. *Reopens when someone other than the author needs
  to run the app without a terminal.*
- **A shell toggle.** Tool policy is the engine's. *Reopens if ds4-engine
  adds a spawn-time tool-policy flag worth a Settings control.*
- **The catalog loader's pid-reuse window.** There is a small window before
  SIGKILL in which the pid could be reused. *Reopens if seen live.*
- **SU.3's leftover.** An Xcode Debug run with the memory widget toggling
  is still unverified (its `start()` test landed in SU.5a1). *Reopens: the
  crash, if a Debug run shows it.*

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
- **A `files --json` command,** for the `@` picker above.
- **A second `/rewind` in a rewound session goes wrong** (live, 2026-10-13,
  sessions `20261013-121126` and `-121133`). In a session resumed with
  `--rewind-to 1` (one turn), `/rewind 1` was refused with `--rewind-to 0`
  ("after prompt 0"). The relaunch then resumed two turns, one of them the
  turn the first rewind removed, and dropped the newest. SwiftStar showed
  exactly what the engine sent. Seen with the `/rewind` queued behind a busy
  turn; the unqueued case wasn't tried.
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
