# Roadmap

> **Planning surface, not the front door.** What's in flight, what's next,
> and the Backlog. Start with [`README.md`](README.md); the settled design is
> [`BRIEF.md`](BRIEF.md), how work runs is [`docs/sdd.md`](docs/sdd.md), and
> closed history is [`docs/history.md`](docs/history.md).

## Now

- **Next:** the owner's acceptance of [SU.18](#phase-su-swiftui)'s spec, `--allow-bash`. Also open: SU.7c (below), AN.3 after the AN.2 click-through. The owner's live checks of SU.6f–SU.11 and SU.7b passed in the app on 2026-10-17: prompt history, ⌘+/⌘−, the fade, a new conversation's row, the rate tooltip, the Recent menus and the mid-turn alert.
- **Next in AN:** [AN.3](#phase-an-analyze), remedies (not brainstormed); the owner's app click-through of AN.2 is open.
- **Blocked on the engine:** more than one window. (Showing the edited copy
  of a file is done: SU.16 reads the receipt's `worktree_path`.) *EN.2's check (2026-10-17): the
  engine allows one engine per process, not per machine, so windows may be
  limited only by GPU memory ([spec §5](docs/superpowers/specs/2026-10-17-en2-engine-catch-up-design.md#5-risks-and-a-finding)).
  Reopening SU.7c is the owner's call.*

## Phase EN: the engine contract

One cycle per ds4-engine landing that SwiftStar catches up to.

| # | Cycle | Direction | Status |
|---|---|---|---|
| EN.1 | Catch up to `5451cd7d` | Drop a saved model the engine no longer offers; show `tool_rejected` as a declined card; honour `relaunch` for `/model`, `/rewind` and `/resume`; dedupe narration and answer if they repeat; fix `just capture` and re-record on the 27B | done 2026-10-13: live on the 27B, the stale model, `/rewind 1` and a model switch worked through the controller (no window clicks). [spec](docs/superpowers/specs/2026-10-13-en1-engine-catch-up-design.md), [plan and Result](docs/superpowers/plans/2026-10-13-en1-engine-catch-up.md) |
| EN.2 | Catch up to `a84b79bd` | Show the startup lines (baseline, env sync, AGENTS.md), conversation-state loads, what a prefix miss changed, `git`/`test` cards, a typed `/analyze`, and the catalog's sizes; re-check engine requests; re-record on the 27B | done 2026-10-18: the engine's start-up lines and card, saved-state loads, a miss's cause, `git`/`test` cards, sizes in the menus; re-recorded on the 27B at `a84b79bd`. [Spec](docs/superpowers/specs/2026-10-17-en2-engine-catch-up-design.md), [plan and Result](docs/superpowers/plans/2026-10-17-en2-engine-catch-up.md) |

## Phase AN: Analyze

Learn which session telemetry matters by reading it, then move what proved
useful into ds4-engine. [Spec](docs/superpowers/specs/2026-10-13-an-session-analysis-design.md).

| # | Cycle | Direction | Status |
|---|---|---|---|
| AN.1 | The report | `just last` and `/last`: the newest session's failed and useless steps, time, per-pause rates and raw signals, from the session directory with no model call | done 2026-10-13: [plan and Result](docs/superpowers/plans/2026-10-13-an1-session-report.md) |
| AN.2 | Analyze and Done | Analyze on the last answer resumes the session as a fork, shows the report and asks about it there; Done resumes the original, so the main context returns as it was | done 2026-10-13: live, fork 3 s and Done 2.9 s, twice. [Plan and Result](docs/superpowers/plans/2026-10-13-an2-fork-and-return.md); the `/rewind` attempt [stopped](docs/superpowers/plans/2026-10-13-an2-analyze-and-done.md#result) |
| AN.3 | Remedies | Suggest and apply fixes from the flags, applied after Done in the main session | not brainstormed |
| AN.4 | Into ds4-engine | Analyze renders ds4-engine's `ds4-dogfood report --json`. `session_last.py`, its rules and its math go; what the report lacks is [ds4-engine#246](https://github.com/pauleveritt/ds4-engine/issues/246) | done 2026-10-17 on `ds4-session-report/2` (#247): SwiftStar's own rules and math are gone, and the report shows the earlier-sessions chain and per-call loop guards. [Plan and Result](docs/superpowers/plans/2026-10-15-an4-engine-report.md) |

AN follow-ups, from AN.2's Result and final review, for the next AN cycle:
- **The report follows `resumed_from`.** After one Analyze and Done, the
  main session is a new directory, and a second Analyze reported "no flagged
  steps" for a session whose earlier turns had one (live, 2026-10-13).
  *Closed by AN.4 on `/2` (2026-10-17):* the report names the chain
  (`earlier[]`), but it doesn't merge the earlier sessions' flags.
- **A resumed-then-answered fixture,** so Done's return can be tested over
  the fake engine. *The fixture is `resumed-answered.ndjson` (EN.2,
  2026-10-18); the test is still to write.*

## Phase SU: SwiftUI

| # | Cycle | Direction | Status |
|---|---|---|---|
| SU.1 | SwiftUI modernisation | `@Environment` controller, `.onSubmit` composer, `.defaultScrollAnchor` transcript, closing the last window quits | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su1-swiftui-modernisation-design.md), [plan](docs/superpowers/plans/2026-10-03-su1-swiftui-modernisation.md) |
| SU.2 | Testable view logic | Move view-adjacent logic into Kit, with tests | done 2026-10-03: [spec](docs/superpowers/specs/2026-10-03-su2-testable-view-logic-design.md), [plan](docs/superpowers/plans/2026-10-03-su2-testable-view-logic.md) |
| SU.3 | Preview adoption | A fixture-backed `#Preview` on every view | done 2026-10-04: views moved to the `SwiftStarUI` library so Xcode can preview them. [spec](docs/superpowers/specs/2026-10-03-su3-preview-adoption-design.md), [plan](docs/superpowers/plans/2026-10-03-su3-preview-adoption.md) |
| SU.4 | Xcode-first UI loop | Xcode 27 and its agent as the place UI work happens: feature folders, previewable parts, `RenderPreview` before a UI change is done | done 2026-10-04: [spec](docs/superpowers/specs/2026-10-04-su4-xcode-first-ui-loop-design.md), [plan](docs/superpowers/plans/2026-10-04-su4-xcode-first-ui-loop.md), [handoff](docs/superpowers/research/2026-10-04-su4-handoff-brief.md) |
| SU.5 | Cleanup and test consolidation | Remove dead code, fossils and the audit's bugs; move view logic into Kit; fold tests into tables with shared support | done 2026-10-13: 230 tests → 130; integration 13–19 s, from ~29. [5a1](docs/superpowers/plans/2026-10-13-su5a1-bugs-and-plumbing.md), [5a2](docs/superpowers/plans/2026-10-13-su5a2-kit-moves-and-tidy.md), [5b](docs/superpowers/plans/2026-10-13-su5b-test-consolidation.md), each with its Result. [Spec](docs/superpowers/specs/2026-10-04-su5-cleanup-and-test-modernisation-design.md) as revised |
| SU.6 | UI tweaks | A punch list of small UI fixes and engine information worth showing (below) | 6a–6f done 2026-10-13, 6g 2026-10-14, each with its plan and Result: `docs/superpowers/plans/*-su6*.md`. The last item closed with EN.2 (2026-10-18) |
| SU.7 | Project focus, switching and resume | The project as the window's identity; its past sessions in the sidebar, resumable; quick, deliberate switching between projects | 7a and 7b done 2026-10-13: this project's conversations in a sidebar; switching asks first mid-turn; the Recent menus (toolbar, Open Recent, Dock) resume a project's newest conversation. Plans: [7a](docs/superpowers/plans/2026-10-13-su7a-sessions-and-resume.md), [7b](docs/superpowers/plans/2026-10-13-su7b-switching-projects.md). 7c (windows) waits on the engine |
| SU.8 | Prompt history | ↑/↓ in the composer steps through earlier prompts | done 2026-10-13: this conversation's typed prompts, while the field is empty or unedited. [Plan and Result](docs/superpowers/plans/2026-10-13-su8-prompt-history.md) |
| SU.9 | Font size | One setting scales every text in the window: 5 sizes, the middle the default; ⌘+ and ⌘− after 7b lands | done 2026-10-13: 14–24 pt, 18 the default, under a new key; the shortcuts wait in the punch list. [Plan and Result](docs/superpowers/plans/2026-10-13-su9-font-size.md) |
| SU.10 | Status bar rates | The two token rates as steady numbers, explained by a tooltip | done 2026-10-14: prefill / generation as bare numbers in fixed slots; the tooltip names them as session averages. [Plan and Result](docs/superpowers/plans/2026-10-14-su10-status-rates.md) |
| SU.11 | The conversation first | Toolbar menus with icons, the window titled and the list selected by the conversation, New Conversation in the list, even inspector type | done 2026-10-14, checked in the gallery: icons in every menu, the window titled by the conversation, its row listed and selected, New Conversation first in the list. [Plan and Result](docs/superpowers/plans/2026-10-14-su11-conversation-first.md) |
| SU.12 | The gallery app | The real window and menus over fixtures, no engine, for checking toolbars and menus by screenshot | done 2026-10-14: `SwiftStarGallery` and `Tools/window-shot.sh`; the agent captures the real window. [Plan and Result](docs/superpowers/plans/2026-10-14-su12-gallery.md) |
| SU.13 | Two leftovers | The memory widget's crash check, in a gallery Debug run (SU.3's leftover); the report card's wide tables at narrow widths (from AN.2) | done 2026-10-14: no crash in 41 flips; wide tables scroll with a scroller, via `pauleveritt/MarkdownView`. [Plan and Result](docs/superpowers/plans/2026-10-14-su13-two-leftovers.md) |
| SU.14 | The `@` file picker | Typing `@` in the composer offers the workspace's files; choosing one inserts `@path`, which the engine expands; the `mentions` event shows what was attached | done 2026-10-14: `@` offers the workspace's files as the TUI ranks them; the engine attaches; an attached/missing line under the prompt; the owner tried it. [Plan and Result](docs/superpowers/plans/2026-10-14-su14-file-picker.md) |
| SU.15 | Colored code in tool cards | A tool card's result preview colored by its file's language, with the highlighter answers' code blocks already use; Markdown as colored raw text | done 2026-10-14: a card's result colored by its file's language, light and dark; Markdown as colored raw text. [Plan and Result](docs/superpowers/plans/2026-10-14-su15-colored-code.md) |
| SU.16 | Files as links | Every file reference opens Quick Look and looks like a link: tool card headers, `@` attachments, code spans in answers that name a real file; the engine's edited copy while its session runs | done 2026-10-18: links in the link color everywhere; the fork's AppKit link clicks never reached a handler, fixed in SwiftStar. [Spec](docs/superpowers/specs/2026-10-18-su16-files-as-links-design.md), [plan and Result](docs/superpowers/plans/2026-10-18-su16-files-as-links.md) |
| SU.17 | The review's fixes | An external review of `main` at `6f1eac0`: nine correctness findings, smaller defects, cuts and stale docs | done 2026-10-14: [plan and Result](docs/superpowers/plans/2026-10-14-su17-review-fixes.md) |
| SU.18 | Run with `--allow-bash` | A Settings toggle spawns the engine with `--allow-bash`; a `run` that fell back to bash says so on its card, with its exit and time; the Session card says bash is on; what the wire lacks goes to the engine | spec written 2026-10-18, awaiting the owner. [Spec](docs/superpowers/specs/2026-10-18-su18-allow-bash-design.md) |

### SU.6 punch list

- **Engine information worth showing** (held back from SU.6g; needs a look
  at what the engine sends):
  - start-up timings: `candidate_ready`, `index_primed`
  - the engine's stderr start notices
  - model sizes from `plan_gib` and `size_bytes`; drop the catalog fields
    the engine never sends

  *Taken into EN.2 (2026-10-17): its D2, D7 and D8. SU.6 closes with EN.2.*

## Backlog

Deferred, each with the condition that reopens it.

### Front-end

- **An Apply button.** Applying stays a terminal step:
  `ds4-dogfood apply <id>`. *Reopens if copying that command becomes daily
  friction and the engine offers a machine-readable apply.*
- **Changed files after each turn.** Most agents end a turn with the files
  it changed, often with `+`/`−` counts and a link to the diff. SwiftStar
  could list them under the answer, each opening a colored Quick Look of
  the changed copy; diffs only if they come cheap. No engine change needed:
  the session directory's `receipt.json` (refreshed at every pause) names
  the candidate worktree, and `candidate.diff` holds the changes since the
  session began, so a turn's files are the difference from the last pause.
  *Reopens when the owner picks it up (filed 2026-10-14).*
- **Token streaming.** The engine's seam is the pause, never a per-token
  callback. *Reopens only if ds4-engine changes that.*
- **Packaging ds4-engine inside the `.app`.** Today the user installs it
  with `uv tool install`. *Reopens when someone other than the author needs
  to run the app without a terminal.*
- **A shell toggle.** Tool policy is the engine's. *Reopens if ds4-engine
  adds a spawn-time tool-policy flag worth a Settings control.* It may have
  one now: `--allow-bash` (next entry).
- **Run with `--allow-bash`, and show when a call fell back to bash.**
  - **The flag:** `tui --allow-bash` is ds4-engine's RUN.2 experiment. `run`
    maps a simple `cat`, `ls` or `grep` onto that tool, and runs anything
    else as `bash -c` in the sandbox (`tui_cli.py:623-630`,
    `driver.rs:3312-3316` at `a84b79bd`). Its default is `config.toml`'s
    `run_bash`, else off.
  - **Wanted:**
    - SwiftStar can spawn with it, from Settings or a toggle.
    - A tool card shows which path a call took. A `run` the engine mapped
      onto a tool looks like that tool. A `run` that fell back to bash says
      so, with its command.
  - **To check first:** whether the NDJSON tells a mapped call from a
    direct one, and a bash run from a refused `run`. If it doesn't, that's
    an engine request.
  - *Picked up as [SU.18](#phase-su-swiftui) (2026-10-18). The wire tells a
    bash run by `op: "run"` with no path, but carries neither its command
    nor a mapped call's origin; see the spec.*
- **Watching prefix effectiveness.** Whether the prompt-prefix cache is
  earning its keep. Today the inspector shows only the latest `prefix_cache`
  event (`hit`/`miss`, tokens, load or fill time), and the AN report counts
  outcomes per session. Wanted: hits and misses over a session and across
  sessions (from `operator-events.jsonl`), the time a hit saved (its load
  against a miss's fill for the same model), and a miss's cause, once the
  engine reports it; perhaps a status-bar or inspector trend, perhaps a
  `just` report first. *Reopens when the owner picks it up (filed
  2026-10-14); the two gaps are under Engine requests. Since 2026-10-17,
  a miss's cause is live (EN.2), and the report has each event's time saved
  or spent (AN.4); across sessions is still open.*
- **The power throttle knob.** The P-era app had a power-saving switch:
  on by default, it spawned the engine at `--power 70`, off at the
  engine's 100, never for the SSD-streaming Laguna variants, which refuse
  under 100 (`1ea864d`, `6af55c0`). `ds4-dogfood tui` has no such flag; its
  migration table maps `--power` to none (`docs/tui.md`). *Reopens when
  ds4-engine offers a throttle (filed 2026-10-14; the request is below).*
- **The catalog loader's pid-reuse window.** There is a small window before
  SIGKILL in which the pid could be reused. *Reopens if seen live.*

### Engine requests

Things SwiftStar can't show or do until ds4-engine changes. Raise them
there.

- **The `session` event doesn't report the candidate worktree.** So Quick
  Look opens the checkout's copy, not the edited one. *Found 2026-10-14:
  the session directory's `receipt.json` names it (`worktree_path`); SU.16
  can use that, so this request is no longer needed.*
- **A prefix-cache miss doesn't say why.** The key covers the engine, model
  file, shaders, context size, DFlash and the prompt's tokens
  (`docs/tui.md`); the `miss` event names none of them, so a miss after an
  update can't be told from a cold cache. *Answered (ds4-engine `3db6dcaf`):
  each entry keeps its key parts, and a miss's `changed` names the ones that
  differ, live and in the report (`prefix_cache.rs:75-86`). EN.2 shows it.*
- **Live-prefix reuse between turns isn't recorded.** The engine's cost
  panel assumes the live prefix was reused, and notes that a rebuild "is
  not visible in the capture"; so its share of a turn's prefill can't be
  shown. *Re-checked at `a84b79bd`: still open (`capture.rs:339`). Resume
  alone is now recorded, as `conversation_state`.*
- **No power throttle.** The old engine's `--power` percent has no
  `tui` equivalent, so SwiftStar can't offer its power-saving switch again
  (the Front-end backlog's knob). *Re-checked at `a84b79bd`: still open.*
- **`models --json` sends no `default_model_id`.** So "Engine default"
  can't name the model it means. *Re-checked at `a84b79bd`: still open; the
  default is internal (`models.py:170`). EN.2 names the context and plan
  instead.*
- **`prefill_tokens` isn't prefill.** It's the transcript length minus evals
  (`operator_telemetry.py:101-113`), so tokens the engine didn't prefill
  count as prefilled:
  - A prefix-cache hit's tokens. Since SU.6b, SwiftStar leaves those out.
  - A resumed conversation's loaded KV. Session `160812` read about 106,700
    tok/s.
  - After `/clear` or a compaction, the count collapses.

  Analyze no longer reads this count: since AN.4, its syncs come from the
  capture (`report`). The status bar's session rates still do.
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
  *Fixed by #226 (2026-10-15): the resumed turns now stop where each rewind
  cut its parent (`sessions.py:296-321`). The `--rewind-to 0` argv is by
  design: the count is the session's own prompts (EN.2, D9).*
- **What `report --json` lacked** ([ds4-engine#246](https://github.com/pauleveritt/ds4-engine/issues/246),
  AN.4). *Answered by #247 as `ds4-session-report/2` (2026-10-16); AN.4
  reads it:*
  - a label on 33 to 64-token syncs, which read as slow
  - `resumed_from` and `rewound_to`
  - whether each prompt was answered
  - engine errors per prompt
  - the call each loop-guard notice hit
  - candidate-ready time
  - files changed
  - `closed` and `telemetry_ok`
  - the raw signals
- **`resumed.turns` carries no narration.** So a 27B turn rebuilt after a
  rewind or resume shows only its one-line summary, not the full reply
  (SU.6a). *Re-checked at `a84b79bd`: still open (`sessions.py:45-50`).*
- **Watch, not a request: the Satyrn rename.** `ds4-dogfood` and the
  `~/.local/state/ds4-engine` paths may be renamed. SwiftStar would need to
  change `EngineCommand.executableName`, and probing both names is the
  likely fix. *Not happened at `a84b79bd` (`pyproject.toml:13`).*

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
