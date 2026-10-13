# SwiftStar AN design: analyzing a session

**Date:** 2026-10-13
**Status:** approved by the owner 2026-10-13. **Revised the same day**
(fork by resume, at the end): the revision awaits owner review.
**Phase:** AN (Analyze), a new named phase. This spec covers AN.1 and AN.2
in full and names AN.3 and AN.4.
**Evidence:** session directories under `~/.local/state/ds4-engine/sessions/`
read on 2026-10-13, chiefly `20261013-123136-swiftstar` (cited as "123136").
`E/` is `../ds4-engine` at `5451cd7d`. `M/` is `../mellum-worker` at
`b1b4abf`.

## Goal

After a session, or between prompts, the owner can see quickly and without
a model call where the session went wrong and where its time went, and can
then talk it through with the model **without the analysis staying in the
main conversation**.

The phase is exploratory. It runs in SwiftStar while we learn which
numbers matter, and its last cycle moves what proved useful into
ds4-engine, which owns the session files.

The precedent is mellum-worker's `/mellum last` (`M/extensions/mellum-last.ts`,
v0.1.7): the newest run as a Markdown table with no model call, so a short
follow-up question replaces a long telemetry prompt.

## Decisions

The owner chose each of these on 2026-10-13.

**D1. A standard-library Python script, not Swift and not a prompt.**
- It is deterministic and costs no model call.
- It reads the engine's own files, in the engine's language, so AN.4 is
  close to a copy.
- A prompt-only slash command was rejected: not deterministic, and a model
  call every time. A Kit reader was rejected: it would be rewritten in Python
  for AN.4.

**D2. It reads the session directory directly.**
- The newest session is found with the engine's own CLI,
  `ds4-dogfood sessions --json --source <git root> --limit 1`.
- Everything else is read from files: the events log, the receipt, the
  capture and the diff.
- The two CLIs' JSON alone (`sessions --json`, `operator_cost --json`) were
  rejected: neither has steps, guards, rejections or tool failures.
- The engine's private Python modules were rejected: they are reached
  through uv's tool venv, and they are hard to change while learning.

**D3. Failures first.** The report leads with the steps that failed or
did nothing useful. Then it covers where the time went, whether context is
hurting speed, what the model did, and what went wrong. Last comes a raw dump
of the signals that only this architecture records.

**D4. Analysis happens in the live session and is thrown away by rewind.**
- A fork was considered: resume the session into a new one for the
  analysis, then resume the original. It was rejected because it costs a
  relaunch at both ends.
- Rewind costs one relaunch, at the end, and the owner accepts losing what
  was said during analysis.
- It is not lost on disk: rewinding starts a new session directory, so the
  analysis stays readable in the old one.

**D5. Lean (the sanity check).** Each of these was cut, and returns only with
evidence:
- joining events to steps
- an "empty result" rule
- `--prompt` and `--source`
- a versioned JSON contract
- an events-only fallback
- a second fixture
- a chart card

## 1. What a session directory holds

Read from 123136. Event `schema_version` is 1; capture `schema_version` is 18.

- **`operator-events.jsonl`.** The same events as the `--ndjson` wire, each
  with `seq`, `turn` (the prompt index) and `elapsed_ms`. 123136 has
  `session`, `resumed`, `candidate_ready`, `memory`, `where`, `prompt`,
  `native_start`, `native_end`, `prefix_cache`, `receipt_start`,
  `receipt_end`, `index_primed`, `checkpoint`, `thinking`, `narration`,
  `tool_start`, `tool_end`, `tool_result`, `tool_rejected`, `answer` and
  `closed`.
- **`receipt.json`.** It names the source, the commit, `capture_path` and
  `diff_path`.
- **The capture, `run-*.json`.** Its `turns` are **steps**, one per model
  pause. A step has `tokens` and `context_used`. A tool step also has
  `tool.{name, args, result_ok, result_text, bytes_total, bytes_shown}`.
  At the top level the capture has:
  - `user_turns`
  - `outcome`
  - `token_counts`
  - `timing.{per_sync_ms, per_eval_ms, wall_ms}`
  - `loop_guards.{repeated_call, call_cycle, answer_cap, self_copy, already_shown}`
  - `constraint`
  - `think_inert_openers`
- **`candidate.diff`.**

123136 has 40 steps over 4 prompts:
- **Answer steps,** with no `tool`: 0, 20, 32 and 39.
- **`host_results` bookkeeping steps,** with no tokens.
- **Step 17:** `run`, `result_ok` false, with result text
  `Tool error: unknown tool: run…`.
- **Steps 36 and 37:** re-reads answered `[Already shown above: …]`, which
  matches `loop_guards.already_shown` = 2.

## 2. AN.1: the report

### 2.1 Command

`Sources/SwiftStarEngine/Resources/session_last.py`:
- a SwiftPM resource of the `SwiftStarEngine` target, so the app finds it
  through `Bundle.module`
- `just last` and the tests use the same file
- standard library only; it runs with `python3 -I`

```text
session_last.py [--session PATH] [--json]
```

**Finding the session:**
- `--session PATH` is used as given.
- Without it, the script runs `ds4-dogfood sessions --json --source <git
  root of cwd> --limit 1`. That is the only subprocess the script ever starts.
  `ds4-dogfood` is found from `$DS4_DOGFOOD`, then `PATH`, then
  `~/.local/bin`.

**Output:** Markdown on stdout. With `--json`, the report as a dict
(`json.dumps`).

**Errors** go to stderr, with exit 1:
- no session found (naming the repo and the command that was run)
- a missing file

An unknown `schema_version` adds a warning line and does not refuse.

**Pure functions:**
- `load(dir)`
- `steps(session)`: groups steps into prompts. An answer step closes a
  prompt.
- `flags(steps)`: returns the flags and the checks that ran
- `summary(session)`
- `signals(session)`
- `report(session)`
- `markdown(report)`

### 2.2 Output, in order

1. **Header:** session id, model, context size, wall time, outcome, and
   `resumed_from` / `rewound_to` when present.
2. **Flagged steps:** prompt, step, what the step did (tool and path, or
   answer), the rule and its evidence. When nothing is flagged, it prints
   "no flagged steps" and names the checks that ran.
3. **Summary table:**

   | Row | Content |
   |---|---|
   | Time | Wall time; start-up (`candidate_ready`, prefix-cache fill or load, first `native_end`); model time (`native_end` durations) against tool time (`tool_end` durations) |
   | Context and speed | `ctx_used` first → last; prefill and generation tok/s **per pause**, from deltas of the session-cumulative `checkpoint` timings, shown as first / median / last, and the slowest pause |
   | Work | Prompts, steps, tool calls by name, `tool_rejected` by reason, files in `candidate.diff` |
   | Ending | How each prompt ended (answer, stop, error); `closed`; `telemetry_ok` |
   | Health | Peak `gpu_allocated_bytes` against `gpu_budget_bytes`, compactions, `error` events |

4. **Signals,** raw:
   - `loop_guards`
   - `constraint.masked_token_count`, `removed_probability_mass` and
     `forbidden_argmax`
   - `think_inert_openers`
   - `citation_corrections`
   - prefix-cache hits and misses
   - syncs under 1 ms
   - the DFlash state
   - the number of `host_results` steps
   - total result bytes against bytes shown

Table cells are escaped, as `M/extensions/mellum-last.ts` `cell()` does:
newlines become spaces and `|` is escaped, with the backslashes before it
doubled.

### 2.3 Flag rules

`host_results` steps are never flagged.

- **F1, tool failed:** `result_ok` is false. The evidence is the first line
  of `result_text`.
- **F2, engine failure:** in the prompt's event window, a `native_end` whose
  `status` is not `ok`, or an `error` event.
- **F3, unanswered prompt:** the prompt has no answer step.
- **U1, guard notice:** the `result_text` is one of the engine's guard
  notices. The marker strings come from `E/` source with a citation, per
  BRIEF's rule for engine facts. The count of U1 markers found is checked
  against the `loop_guards` totals, and any difference is shown.
- **U2, plain repeat:** the same tool and arguments as an earlier step in
  the session, from any prompt, with
  no `edit` or `write` to that path in between. A re-read after an edit is
  verification; 123136's step 18 is one and is not flagged.

### 2.4 Wiring

- **Justfile:**
  - `last *ARGS` runs the script
  - `test-tools` runs `python3 -I -m unittest` over `Tools/tests`
  - `test` also runs `test-tools`
- **`.claude/commands/last.md`:** `/last` runs `just last $ARGUMENTS` and
  shows the result. It tells Claude to answer follow-up questions from the
  report, and to open the session files only for the steps asked about.
- **Fixture:** `fixtures/sessions/123136/` holds 123136's events, receipt,
  capture and diff. It has no `conversation.kv` and no `rewind/`. The
  receipt's `capture_path` is rewritten to be relative, and the change is
  noted in `fixtures/sessions/provenance.md`, which also names the engine
  commit and the model.

### 2.5 Tests

`Tools/tests/test_session_last.py`, using `unittest`, with no subprocess and
no network.

**Against the fixture:**
- `test_123136_accepted`: 4 prompts, 40 steps.
- `test_123136_flags`: step 17 has F1, with evidence naming `run`; steps 36
  and 37 have U1; step 18 has no flag.
- `test_123136_guard_totals_agree`: 2 U1 markers, matching
  `loop_guards.already_shown`.

**Rule tests over small step lists built inline, each with a sibling that
passes:**
- `test_repeat_without_edit_flagged` / `test_repeat_after_edit_not_flagged`
- `test_prompt_without_answer_flagged` / `test_prompt_with_answer_not_flagged`

**Output tests:**
- `test_per_pause_rates_are_deltas`: two cumulative checkpoints give the
  delta rate, not the running average.
- `test_no_flags_names_checks`
- `test_markdown_cell_escaping`

Every test is shown to fail once by breaking the rule it pins, and the plan
records the break. No test asserts on source text.

**Live checks, recorded in the plan's Result:**
- `just last` on this repo
- `just last --session` on an older session
- `/last` in Claude Code

## 3. AN.2: Analyze and Done

### 3.1 What the owner sees

1. On the last answer, an **Analyze** link next to the telemetry caption
   (`Sources/SwiftStarUI/Session/TranscriptRowView.swift:25`). It shows only
   when `canAnalyze` is true.
2. Clicking it:
   - appends a **report card**: a new `TranscriptRow.report(String)`, tinted,
     rendered with `MarkdownText`, with a Copy Markdown button
   - sends the report and a fixed instruction as a prompt: "Explain each
     flagged step: what the model was trying to do, and why it failed or
     was wasted. Then propose remedies. Don't edit files."
3. **While analyzing:**
   - a banner reads "Analyzing — Done discards everything below and returns
     to prompt k", with a **Done** button
   - the composer is tinted, with the placeholder "Ask about the analysis…"
   - the card and every row after it carry a tinted left rule

   Follow-up prompts go through the same composer into the same session.
4. **Done:**
   - sends `/rewind <prompts now − k>`
   - the existing relaunch path resumes the session at prompt k and rebuilds
     the transcript
   - the divider reads "Analysis ended — back at prompt k"
   - the candidate's diff is restored with the conversation, so edits made
     during analysis are undone (`E/docs/tui.md`, "Rewinding a prompt")

### 3.2 Pieces

**Kit** (`EngineSessionModel` and `EngineCommand`):
- `sessionDirectory`: set from the first `checkpoint` snapshot's
  `capture_path`. Today the directory is only learned at `closed`
  (`EngineWireParser.swift:140`).
- `canAnalyze`: idle, a directory is known, and not already analyzing.
- `beginAnalysis()`: records `k`, the prompts answered so far.
- `analysisDoneCommand`: `/rewind <prompts now − k>`.
- `reportArgv(directory:)`: `/usr/bin/python3 -I <resource> --session <dir>`.
  This is the one place AN.4 changes.

**Engine target:**
- `SessionReportLoader` runs the argv and returns the Markdown or an error,
  shaped like `EngineModelCatalogLoader`.

**UI:**
- the link, the card, the banner and the composer tint
- the touched `#Preview`s are rendered with `RenderPreview`, and both tiers
  pass (CLAUDE.md; the `ui-loop` skill)

### 3.3 Tests

**Fast tier:**
- `k` is captured at Analyze. With `k` = 3 and two follow-ups, Done gives
  `/rewind 3`.
- `canAnalyze` is false while busy, while already analyzing, and with no
  directory, each with a sibling where it is true.
- `sessionDirectory` comes from a recorded fixture's `checkpoint`.

**Integration tier:**
- `SessionReportLoader` against `fixtures/sessions/123136`.
- A missing script and a failing script each give an error, with a sibling
  that succeeds.

### 3.4 Gates, the first tasks of AN.2

If a gate fails, AN.2 stops there, and the failure becomes an engine request.

1. **Repeated rewind.** Analyze → Done twice in one session, live. The
   2026-10-13 bug (ROADMAP, Engine requests: a second `/rewind` in a rewound
   session resumed the wrong turns) is exactly this path.
2. **Reading a live session.** At a pause, the capture is `provisional`.
   The report must be complete from it; if it is not, AN.2 needs a design
   change before going on.
3. **Done end to end.** Time Done at a small and at a large `ctx_used`. The
   relaunch is ~2.5 s on the same model: `candidate_ready` was 2.3–2.5 s in
   sessions 121116, 121126, 121133 and 122439 on the 27B. A model switch
   took 16.7–19.0 s (sessions 121809 and 123136). After the relaunch, "The
   engine refills the restored conversation" (`E/docs/tui.md`), and that
   cost grows with `ctx_used`. If a large refill is slow, AN.2 ships with
   that limit stated, and a request for a fork that keeps the KV state goes
   on file with the measurement.

## 4. AN.3 and AN.4, named

- **AN.3, remedies:** suggest fixes from the flags, and apply them. Because
  Done restores the candidate's diff, a remedy is applied **after** Done,
  in the main session. Brainstormed after AN.2 has been used.
- **AN.4, into ds4-engine:**
  - `ds4-dogfood last [--session] [--json]` takes the script, its tests and
    its fixture
  - `reportArgv` switches to it, and the bundled script is deleted
  - the slow-refill and rewind requests go on file there if they are still
    open

  It opens on the owner's call, once the flag rules and summary rows have
  stopped changing. It owes a recapture only if `last` reaches the wire.

## 5. Done when

- **AN.1:** the tests in §2.5 pass and were each shown to fail; `just last`,
  `just last --session` and `/last` work live; `just test` runs the Python
  tests; the plan's Result is written; the ROADMAP gains the AN table and a
  `## Now` pointer; `just lint-docs` passes.
- **AN.2:** all three gates were run and recorded; Analyze → follow-up →
  Done works live; the previews were rendered and looked at; `just test` and
  `just integration` pass; the ROADMAP row and `just lint-docs` are done.

## 6. Risks

- **The engine's file formats are internal.** A new schema gives a warning,
  not a refusal, and AN.4 removes the coupling.
- **`/usr/bin/python3`** is a shim that offers to install the Command Line
  Tools on a machine without them. This is acceptable for a developer tool
  and goes away at AN.4.
- **U1 markers come from engine text.** A new guard wording would go
  uncounted; the check against `loop_guards` totals makes that visible.
- **Analyzing makes the context grow until Done.** A long analysis at high
  `ctx_used` is slower for the reason BRIEF's finding gives.

## Revision, 2026-10-13: fork by resume, return by resume

Directed by the owner after AN.2's gates. **This supersedes D4 and §3.1's
Done step, and §3.4's gates.** §3.2 and §3.3 change only as described here;
everything else above stands.

### What was measured

From [AN.2's Result](../plans/2026-10-13-an2-analyze-and-done.md#result),
live on `qwen3.8-27b`:
- **A second `/rewind` in a rewound session resumes a removed turn.** Filed
  as [ds4-engine#219](https://github.com/pauleveritt/ds4-engine/issues/219).
- **A first `/rewind 1` at 37,744 tokens rebuilt in 3.6 s, but the next
  prompt took 243 s.** It refilled the whole conversation at about 156
  tok/s, because a rewind snapshot keeps no saved state
  (`E/src/ds4_engine/tui_cli.py:144-158`).
- **Resuming a session with its saved state reached `input` in 4.5 s.** Its
  first prompt at 41,949 tokens then took 1.4 s, with `sync_ms` 393.
- The 17 s that first ruled out a fork was a model switch, not a resume.

### D4, revised: the analysis runs in a fork, and Done returns to the original

- **Analyze:**
  - SwiftStar quits the main session at its pause. The engine saves the
    conversation's state at every wait.
  - It starts `tui --resume <main dir> --source <root> --ndjson`. This is
    the shape of the engine's own `restart_argv` for a session SwiftStar
    started (`E/src/ds4_engine/tui_cli.py:412-416`).
  - The resumed session is the **analysis session**: a new directory with
    the full main context and no refill. The report goes in as its first
    prompt.
  - SwiftStar builds this argv because `/resume` refuses the session it is
    running in ("that is this session", `E/src/ds4_engine/tui_cli.py:938`).
- **Done:**
  - SwiftStar sends `/resume <main id>` from the analysis session.
  - The engine refuses with a `relaunch` argv (TUI.34), and EN.1's
    relaunch path runs it.
  - The main directory is never written to after it ends ("an earlier
    session is evidence", `E/src/ds4_engine/sessions.py`), so the main
    context returns exactly, without the analysis.
- **Pruning is safe.** The engine keeps the 3 newest saved states plus the
  one being resumed (`sessions.py:31`, `tui_cli.py:908`). One analysis
  session between the main session and its return leaves the main state in
  the 3, and the return spares it anyway.
- **Cost:** two resumes, about 4.5 s each, and no refill at the next
  prompt. This is under the owner's 30 s line.
- **Nothing is lost:** the analysis stays readable in its own directory
  (`just last --session`).
- **No `/rewind`,** so #219 doesn't block this.

### §3.1, revised: what the owner sees

1. **Analyze** on the last answer, as before.
2. The transcript shows `Starting analysis…` while the fork starts. It is
   then rebuilt from the main session's turns under the divider
   `Analysis — a copy of this session`, followed by the report card and the
   analysis prompt.
3. **While analyzing:** the banner reads `Analyzing a copy — Done returns to
   the session as it was`, with **Done**. The composer tint and placeholder
   are as before.
4. **Done:** the transcript is rebuilt from the main session, under
   `Analysis ended — back at prompt k`, where `k` is the number of turns
   resumed.
5. A relaunch other than Done during analysis (`/model`, `/resume`, a
   rewind) ends the analysis state with that relaunch's usual divider. The
   main session is still on disk and can be resumed by hand.

### §3.4, revised: one live check first

Before any app code, a throwaway driver over `--ndjson` runs the whole loop:
- a main session with two prompts
- quit, then resume it as the analysis session, then one question
- `/resume <main id>`, then run its `relaunch`

**Pass:** each resume reaches `input` within 10 s, and the first prompt
after each has `sync_ms` under 5,000. The returned session's
`resumed.turns` are the main's two, without the analysis. The main
directory's `conversation.kv` still exists. If any of these fails, AN.2
stops and the owner decides.

### AN.1 additions, from the review

- **A refill flag.** A pause whose `sync_ms` is over 10,000 is flagged, with
  its tokens and time as evidence. The report on the 243 s session said
  "no flagged steps".
- **`/last` points Claude at `conversation.json`** too: what the model saw.

### Still out

- the chart card
- remedies (AN.3)
- making rewind keep saved state: an engine request, not needed by this
  design
