# SwiftStar P28 design: cut over to ds4-engine

**Date:** 2026-09-28  
**Status:** design, for the owner's review  
**Phase:** P28 — ds4-engine cut-over

## Goal

Replace SwiftStar's engine — the `external/ds4` submodule and its
`ds4-agent` binary — with the sibling project
[ds4-engine](https://github.com/pauleveritt/ds4-engine), driven as a child
process over its own NDJSON protocol (`ds4-dogfood tui --ndjson`, TUI.15).
SwiftStar becomes a macOS front-end for one held ds4-engine session: prompt,
transcript, tool cards, per-pause metrics, stop, quit.

This is a hard cut-over with **maximum removal**. At the end the repository
holds no ds4 code, no submodule, no `ds4-agent` wire dialect, and nothing
that duplicates a job ds4-engine now does (tools, worktrees, model choice,
memory admission, session capture, evals).

**This deliberately reopens `BRIEF.md`.** "Architecture, settled" and "The
fork" describe a host-tools, pooled, forked-C engine. The owner directed the
reopening on 2026-09-28; the BRIEF is rewritten as part of this phase, and the
old text survives in git.

## Decisions taken in brainstorming

1. **Hard cut-over.** No switch, no coexistence period.
2. **Wire: `--ndjson`, not `--json-events`.** `--json-events` (TUI.17) would
   let `AgentWireParser` run unchanged, but it is a compatibility shim that
   imitates `ds4-agent`, reports tools as a path only, and could be dropped
   upstream. `--ndjson` is ds4-engine's own protocol and carries richer
   telemetry. SwiftStar gets a new parser.
3. **Both CLIs go.** `swiftstar-eval` and `swiftstar-agenttest` are removed;
   evaluation lives in ds4-engine (`evals/`, `ds4-dogfood -p --json`).
4. **No Apply button.** Engine edits land in the session's `candidate.diff`.
   SwiftStar shows the session directory and the `ds4-dogfood apply <id>`
   command when a session closes; applying stays a terminal step.
5. **Metrics come from the wire only.** Process CPU/memory sampling, IOReport
   power and Metal working-set reads are removed, with the private `IOReport`
   linker setting.

## The live check (2026-09-28)

Two single-prompt runs of `ds4-dogfood tui --ndjson` against this worktree,
Laguna XS 2.1, context 20,000, M5 Max. Both exited 0 in about 7 s. Findings
that shaped the design:

- The first line is `{"kind":"ready","protocol":1}`; turn end is
  `{"kind":"input"}`; shutdown is `quitting` then `close`.
- Tool use arrives as `narration`, `tool_start {op, path}`,
  `tool_end {status, duration_ms}`, `tool_result {result_kind, preview,
  truncated}` — enough for a tool card with a preview.
- There is no live throughput during generation. Each pause emits a
  `checkpoint` whose `snapshot` has `prefill_tokens`, `sync_ms`,
  `eval_count`, `eval_ms`, `output_tokens`; each `answer` has `context_used`,
  `context_size`, `duration_ms`; `memory` has `gpu_allocated_bytes`,
  `gpu_budget_bytes` and `engine_plan`. Metrics are therefore per pause.
  `native_start`/`native_end` bracket the busy interval.
- `status` and `diagnostic` are human text; `diagnostic` repeats the answer
  and a `[ctx n/N]` line.
- Run 1 produced an 8-token Japanese reply and no tool call; run 2, with a
  more directive prompt, read `Package.swift` twice and answered correctly.
  The wire was correct both times; answer quality is ds4-engine's concern,
  not this phase's.

## Architecture after the cut-over

```
SwiftStar.app ──spawn──▶ ds4-dogfood tui --ndjson --source <root> --commit HEAD
   EngineSession  ──stdin──▶ {"kind":"prompt"|"stop"|"quit"}, 0x03
   EngineSession  ◀─stdout── ready / input / event / error / close / …
   EngineWireParser (SwiftStarKit, pure) ─▶ EngineEvent ─▶ transcript, metrics
```

### Units

- **`EngineCommand`** (`SwiftStarKit`, pure). Resolves the executable and
  builds argv: `tui --ndjson --source <project root> --commit HEAD`. Model,
  context size and capture directory are left to ds4-engine's defaults
  (saved model or Laguna XS; largest measured context; a new directory under
  `~/.local/state/ds4-engine/sessions/`). Executable resolution: the Settings
  path if set, else `PATH`, else `~/.local/bin/ds4-dogfood` (a GUI app's
  `PATH` rarely includes uv's tool directory). Replaces `AgentCommand` and
  `AgentDefaultSettings`.
- **`EngineWireParser`** (`SwiftStarKit`, pure, fast-tier). One stdout line
  in, zero or one `EngineEvent` out. Requires `ready` with `protocol == 1`
  as the first line and refuses anything else loudly. Decodes `event`
  payloads by `kind`; unknown kinds become `.ignored`, so upstream can add
  telemetry without breaking SwiftStar.
- **`EngineEvent`** (`SwiftStarKit`). The slimmed successor of `AgentEvent`:
  `ready`, `loading(text)`, `session(id, modelID, contextSize)`,
  `busy`/`idle` (from `native_start`/`native_end`), `narration(text)`,
  `thinking(text)`, `toolStart(op, path)`, `toolEnd(op, path, ok, ms)`,
  `toolResult(op, path, kind, preview, truncated)`, `answer(text,
  contextUsed, contextSize, ms)`, `pause(PauseMetrics)` (from `checkpoint`),
  `memory(allocated, budget, planGiB)`, `interrupted`, `awaitingInput`,
  `error(text)`, `closed(capturePath)`, `ignored`.
- **`EngineSession`** (`SwiftStarAppKit`). Replaces `AgentSession`. Spawns
  the process via the existing `SubprocessRunner`, feeds stdout through
  `LineBuffer` and `EngineWireParser`, publishes `EngineEvent`s. API:
  `start()`, `send(prompt:)`, `stop()` (writes `{"kind":"stop"}`),
  `interrupt()` (writes `0x03`), `quit()` (writes `{"kind":"quit"}`, closes
  stdin, SIGTERM after a timeout). Captures the session directory from the
  `closed` event or the `Session artifacts:` stderr line.
- **`MetricsReducer`** (`SwiftStarKit`). Rewritten to fold `pause`,
  `answer` and `memory` events: prefill tok/s = `prefill_tokens / sync_ms`,
  generation tok/s = `eval_count / eval_ms`, context fill, GPU memory.
- **App (`SwiftStar`).** `AgentController` shrinks to one session's
  lifecycle; the transcript, bubbles, tool cards, Markdown rendering and
  font sizing stay; Settings shrinks to the `ds4-dogfood` path. All prompt
  text, including a leading `/`, is sent to the engine verbatim — ds4-engine
  owns its slash commands.

### Lifecycle and errors

- `input` enables the prompt field. A prompt sent while busy is still sent;
  the engine queues it (32 messages, 32 KiB).
- `error` messages render as an error bubble; the session continues.
- Process exit ends the session with a mapped message: 0 done; 1 failed
  (plus the stderr tail); 2 bad arguments or no model on this Mac; 130
  interrupted; anything else, the raw code.
- A first line other than `ready`/`protocol: 1`, or an unparseable line,
  ends the session with an explicit protocol error naming what was seen.
- `status` text is shown only while loading; `diagnostic`, `queued`,
  `stopping`, `quitting` are ignored.

## Removed

By area. The plan enumerates files; anything not listed under "Kept" is a
removal candidate, and the plan justifies any survivor.

- **Engine and build:** `external/ds4`, `.gitmodules`, the Justfile
  `engine` recipe, `DS4_*` environment plumbing, bundled `golden.*`
  resources.
- **CLIs:** `Sources/swiftstar-eval/`, `Sources/swiftstar-agenttest/` and
  their exclusive support (`EvalArguments`, `EvalExperiment`, `EvalReport`,
  `ArmDiff`, `AgentTestAnalyzer`, `AcceptanceGrader`, `GraderVerdict`,
  `DeepSeekGrader`, `FixtureReplay`).
- **The old wire:** `AgentWireParser`, `WireEventParser`,
  `WireStatusDecoder`, `PoolWireParser`, `AgentCommand`, `SpawnRecord`,
  `PoolPrompt`.
- **Host-run tools:** `HostToolExecutor`, `HostToolConfinement`,
  `ToolCallbackResponder`, `CommandToolRunner`, `ReadWindow`,
  `ReadRepeatCounter`, `ToolCallBudgetTracker`, `ToolResultCondenser`, the
  digest family (`ToolDigest`, `BashDigest`, `RuffDigest`, `TestDigest`,
  `RollingDigest`), `CommandOutput`, `ProjectCommandResolver`.
- **Pool, dispatch, repair:** `PoolEngine`, `PoolOrchestrator`,
  `AgentPoolTurnLoop`, `ActiveWorkerTurn`, `PoolScheduler`,
  `SubagentPoolSize`, `WorkerId`, `WorkerTurnState`, `WorkerContextPolicy`,
  `Dispatch*`, `Handoff*`, `WorktreeDispatch*`, `WorktreeTransaction`,
  `GitProcess`, `RepairLoop`, `PhaseRepair`, `PhasePacketBuilder`,
  `Decompose`, `OrchestrateDirective`, `TextContractHarvest`,
  `LabeledBlockParser`, `Finding`, `ContextAssembly`, `TurnThinkPolicy`.
- **Model management:** `Variant*`, `Feasibility`, `DialLogic`,
  `ModelChoice`, `ModelSwitchDecision`, `GGUFMetadataReader`,
  `DownloadRunner`, `ChunkedDownload`, `MachineEvidence`.
- **Trace and diagnostics:** `TraceParser`, `PairBill`,
  `AdvertisedToolNames`, `DiagnosticsAnalyzer`, `DiagnosticsLogic`,
  `DiagnosticsFixture`, `DiagnosticsModel`, `DiagnosticsView`,
  `TurnAlignment`, `TurnSpan`, `TurnSummary` (if nothing kept reads it).
- **SwiftStar-side capture:** `CaptureWriter`, `CaptureProvenance`,
  `CaptureRetention`, `CaptureUsability`, `CaptureValidity`,
  `SafeAppendFile` (if unused), `RunWorkspace`, the `captures/` tee, and
  `.claude/skills/telemetry/`.
- **Prompt staging:** `SuperpowersBootstrap`, `SkillStager`, the
  `swiftstar-agent` skill resources.
- **Host sampling:** `IOReportPower`, `ProcessStatsCollector`,
  `MetalWorkingSet`, the `IOReport` linker setting.
- **Tests and fixtures:** every test of a removed unit; `fixtures/agent/`,
  `fixtures/agenttest/`, `fixtures/diagnostics/`; `FakeAgentSource`,
  `FakeAppSource`, `FakeSourceLiteral`, `FakeAgentHarness`.

## Kept

`AgentTranscript` (re-fed from `EngineEvent`), `TurnOutcome` (if still
meaningful), `MetricsReducer` (rewritten), `LineBuffer`, `ProjectRoot`,
`PathAbbreviation`, `MarkdownPreprocess`, `TranscriptFontScale`,
`AgentStatusText`, `SubprocessRunner`; the views `MainView`, `AgentView`,
`AgentBubbles`, `AgentToolCardView`, `MarkdownText`, `MetricsView`,
`ValueGaugeView`, `SettingsView`, `InspectorView` (if it survives the
Diagnostics removal); the `FastTierGuard` plugin; the MarkdownView
dependency; `Tools/` entries that serve the app build (`make-app`).

## Testing

- **Fast tier.** `EngineWireParserTests` over fixtures recorded from real
  `--ndjson` runs: the handshake refusal, each event kind, unknown-kind
  tolerance, a malformed line. `MetricsReducerTests` and transcript tests fed
  from the same fixtures. No subprocess (the tripwire still applies).
- **Integration tier.** A small Python stand-in for `ds4-dogfood`
  (`fixtures/engine/fake-ds4-dogfood`) replays a fixture, honouring `prompt`,
  `stop`, `quit`, `0x03` and stdin EOF, and exits with a chosen code.
  `EngineSessionTests` drive start → prompt → answer → quit, stop mid-turn,
  protocol refusal, and each exit-code mapping.
- **Live tier.** `just capture` is rewritten to drive the real
  `ds4-dogfood tui --ndjson` with a fixed prompt set and write
  `fixtures/engine/*.ndjson` plus a `provenance.md` (ds4-engine commit,
  model, context, machine). Never in CI.

## Docs

- `BRIEF.md`: rewrite "Architecture, settled", "The fork", "Testing" and
  "Practical environment" for the subprocess engine; retire the DS4 Control
  and clean-room framing only where it no longer applies.
- `ROADMAP.md`: add the P28 row; update Status on rows whose machinery this
  removes (pool, dispatch, host tools, eval CLI); update `## Now`; close or
  re-home Backlog entries that assumed the fork.
- `README.md`, `docs/glossary.md`, `CLAUDE.md` (drop the telemetry section).
- `just lint-docs` green.

## Out of scope

- Token streaming, host-run tools, a worker pool — none exist upstream.
- An Apply button, a session picker (`--continue`/`--resume`), a model
  chooser. Each is a later, separate phase if wanted.
- Improving answer quality; that belongs to ds4-engine.
- Packaging ds4-engine inside the `.app`. The user installs it
  (`uv tool install` of the wheel); SwiftStar finds it.

## Revisions after the design review (2026-09-28)

An independent review (Fable) checked this spec against ds4-engine's
source. These corrections supersede the text above where they conflict; the
original text stays as written.

1. **Exit codes.** 0 = orderly end with the checkout untouched and the last
   outcome answered or cancelled. 1 = any other orderly end (token, tool or
   context limit, no answer, checkout touched) *or* a failure — message:
   "ended without a clean answer — see the session directory", plus the
   stderr tail. 2 = the engine refused to start (argparse: no model, source
   not a git repo, model file missing, capture dir reused) — message:
   "refused to start: " + last non-empty stderr line. 130 = interrupted.
   An exit before any stdout line is a start refusal, not a protocol error
   (`tui_cli.py:610-641` runs before the relay starts).
2. **Checkpoint snapshots are partial.** A snapshot may be
   `{"status":"unavailable"}` or carry `null`s (`operator_telemetry.py`).
   Every `PauseMetrics` field is optional; a snapshot without `eval_count`
   decodes to `.ignored`. `EngineMemory.planGiB` reads
   `engine_plan.total_gib`.
3. **Session directory and apply id.** `closed.capture_path` is a *file*
   inside the session directory, possibly relative to the engine's cwd. The
   session directory is its parent (resolved against the engine cwd), else
   the `Session artifacts: <dir>` stderr line, which is printed after
   `close`, just before exit. `EngineSession` drains stderr to EOF before
   reporting exit. The apply id is the directory's last path component, not
   `session.session_id`.
4. **Slash commands are not silent.** In stdio mode the engine answers
   `/help`, `/status`, `/clear`, `/export`, `/models` only with `help`,
   `status_report`, `clear`, `exported`, `models` events, and refuses
   `/apply`, `/resume`, `/rewind`, `/model` with `apply_refused`,
   `resume_refused`, `rewind_refused`, `model_refused`. These map to
   `.notice(String)` (a system row) and `.refused(String)` (an error row)
   respectively, not `.ignored`.
5. **Busy is per turn, not per native call.** Tools run between native
   calls, so `native_start`/`native_end` flip mid-turn. A turn is busy from
   `.prompt` to `.awaitingInput`; native events only drive a "generating"
   sub-state. Stop is enabled only while busy, because the engine answers
   an idle `stop` with an `error` line.
6. **No `SubprocessRunner`.** It runs processes to completion with no stdin;
   `EngineSession` uses `Process`/`Pipe`/`LineBuffer` directly, as
   `AgentSession` did, and is `@MainActor` (pipe handlers hop to the main
   actor). `SubprocessRunner` is removed.
7. **Source selection.** The engine needs a git repository. SwiftStar keeps
   its workspace folder picker (default: the last chosen folder) and passes
   that folder's git root as `--source`; a non-repository ends in the exit-2
   message.
8. **Kept, corrected.** `AgentTranscript` and `MetricsReducer` are replaced
   by new `EngineTranscript` and `EngineMetricsReducer`, not re-fed.
   `MetricsView.swift` is already unreferenced and is removed. The view
   helpers `Severity`, `contextSeverity` and `fixedWidth` move from
   `DialLogic` into the app target; `DialLogic` is removed. The model menu
   in `AgentView` goes.
9. **App quit.** Quitting waits for the engine through
   `applicationShouldTerminate` → `.terminateLater`, bounded by the quit
   timeout, so SIGTERM actually runs.
10. **Hidden work.** Also in scope: `pyproject.toml` groups and `uv.lock`
    entries that served removed host tools; `.gitignore` entries for
    `captures/` and `.swiftstar/`; `Tests/SwiftStarKitTests/Fixtures/eval-*`;
    comments in kept app files that name `ds4-agent`/`external/ds4`;
    `docs/remediations.md` missing from the Sphinx toctree (`just docs` is
    red before P28 starts); links to deleted sources in `docs/*.md`.

## Success criteria

1. `git grep -il 'ds4-agent\|external/ds4\|submodule'` over `Sources/`,
   `Tests/`, `Package.swift`, `Justfile` returns nothing; `.gitmodules` is
   gone.
2. `swift build` and `just test` pass; integration tests pass against the
   fake `ds4-dogfood`.
3. A live session in the built app with Laguna XS: a prompt that triggers a
   `read` shows a tool card with a preview and an answer, metrics populate
   after the pause, Stop works mid-turn, quitting leaves no `ds4-dogfood`
   process and prints the session directory.
4. `just lint-docs` green; ROADMAP P28 row present.
