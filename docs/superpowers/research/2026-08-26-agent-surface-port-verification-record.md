# Agent surface port — verification record

*Ported 2026-08-26 on branch `ui-agent-surface-port`, forked from `main`
(`88301c5`). Commit `ebfc046` (the port), plus the review fix on top (ctx-ring
gating). Requirements source: the element inventory in
[`docs/2026-08-26-old-ui-element-inventory.md`](../../2026-08-26-old-ui-element-inventory.md)
(cross-referenced against the screenshot `docs/old_ui.png`) and the
in-conversation decisions it summarizes.*

## What was ported

The DS4 Control agent window (worktree `agent-mode`) into SwiftStar's Agent
tab — the surviving surface after the Chat-retirement decision (Backlog):

- **Composer**: multi-line pill field (1–15 lines, Return sends, Shift+Return
  newline), icon-only send/stop (`arrow.up.circle.fill` ↔ `stop.circle.fill`
  with `.symbolEffect(.variableColor.iterative)`), error line, refocus after
  turn.
- **Workspace**: folder button in the status bar, `~`-abbreviated path,
  `NSOpenPanel` picker, persisted; defaults to the repo root when launched
  from a checkout.
- **Bottom readout bar**: fixed-width `Prompt/Decode` rates + activity message
  (TPS ratcheted controller-side — the DS4 Control `2989d2c` fix, ported as a
  pure Kit function), context-fill ring colored by `DialLogic`'s
  absolute-token severity, agent-memory ring (`ready.planned_bytes`
  denominator, 1s `ProcessStatsCollector` footprint poll), End session.
- **Message rendering**: user prompts as accent pills (new `.user` transcript
  row), collapsible thinking disclosure, markdown prose via the pinned
  `notatestuser/MarkdownView` fork (freeze-safe synchronous sizing — the
  `placeSubviews` spin lesson, ported), rich tool cards (per-tool icons,
  `$ cmd` / `name path` header, Quick Look for write/edit/read, fenced
  syntax-highlighted content gated on the new `finished` flag, `diff_old`/
  `diff_new` tinted blocks, monospace output, red failure banner).

## Verification evidence

- **Fast + integration tier**: 572 tests / 78 suites green
  (`SWIFTSTAR_INTEGRATION=1 swift test`), including 14 new/updated tests
  (TDD: red first for `PathAbbreviation`, `AgentStatusText`,
  `MarkdownPreprocess`, `ToolCardEnrichment`).
- **Bundle selftest**: `DS4_SELFTEST_MARKDOWN=1` → `DS4_SELFTEST_MARKDOWN: OK`,
  exit 0 (the dependency's resource-bundle path that crashed the shipped DS4
  .app — ported the guard, wired at launch).
- **Live wire probe** (real engine, `Laguna-XS-2.1-Q4_K_M`, app's exact argv,
  isolated lock): confirmed field-by-field that the enriched model's inputs
  are on the real wire — `param_begin.kind` (`path`/`content`), `tool.name`,
  `param_value.s`, `finish.calls`, `ready.planned_bytes`, `status`
  state/rates/ctx, `tool_request` name+params. Evidence at
  `/tmp/swiftstar-probe/wire.ndjson`.

## Review outcome

Self-review per the requesting-code-review template (no subagent dispatch
available in this harness — recorded honestly). One **Important** issue
found and fixed: the context ring was not gated on the agent being up
(`lastStatus` persists after stop), so a stale ring rendered while stopped;
it is now gated on `isUp` like the memory ring. Minors noted, not blocking:
`ToolParam.kind` is `var` (memberwise-default pattern) rather than `let`;
`deinit` doesn't explicitly cancel the memory poll task (weak-self loop
ends it); `StreamingMarkdownText` collapsed into one `MarkdownText` (the two
were identical in the source; the transcript coalesces in place).

## Follow-on review fixes (round 2)

Second review pass requested by the author; all findings acted on:

- **Workspace default anchored to the executable, not cwd** — `projectRoot()`
  now walks up from `Bundle.main.executableURL` (`.build/debug/SwiftStar` →
  the checkout) via a new pure, tested `ProjectRoot.locate(anchor:)` in Kit.
  A cwd-derived default confined the agent to whatever repo the app was
  launched from — a shipped .app (no `.git` above it) falls back to home as
  before. (`ProjectRootTests`: 4 tests.)
- **Memory-ring plan keyed by model** — `lastPlannedBytes` is now paired with
  `lastPlannedModel` and the ring only uses it when it matches the running
  model, mirroring EngineController's stale-plan guard.
- **Memory-ring fraction clamped at 1.0 + over-budget tooltip** — footprint
  is resident (includes the mapped model) so it can exceed the planned
  budget; the ring reads "full" and the tooltip explains over-budget rather
  than leaving an unexplained critical color. Color still uses the true
  fraction.
- **Rates reset at turn start** — `send()` zeroes the ratcheted rates so a
  new turn never shows the previous turn's numbers while fresh status events
  are pending.
- **`deinit` cancels the memory poll** (`memoryTask` marked
  `nonisolated(unsafe)`, matching the file's `process`/`logHandle` pattern).
- **`ToolParam.kind` is `let`** via an explicit init (default `""`),
  restoring immutability.
- **Selftest hardened** — `DS4_SELFTEST_MARKDOWN=1` alone no longer exits the
  app at launch; the check also requires `--markdown-selftest`. Verified:
  env-only stays running, env+arg exits 0 with `DS4_SELFTEST_MARKDOWN: OK`.
- **Comment typo fixed** (`//-is` line wrap).

Re-verified after the round: 576 tests / 79 suites green (fast +
integration), bundle selftest green under the new contract.

## After the merge (same day)

### Later same day — Chat retired, pool proven, orchestrate in-process

- **Headless spike (shell on)**: the spike prompt ran against the real engine
  with `--shell on` — `bash` entered the tool mix (6 calls: `git log`, reads)
  alongside `read`/`list`, confirming the shell lever; but think=high dominated
  (1,232 think events) and the model never dispatched to the pool worker on
  its own.
- **Chat surface retired** (`f546671`): ChatView, EngineController, the whole
  `ds4-server`/SSE path (ServerCommand, SSEParser, ChatTranscript, Supervisor,
  BootLineParser) and the fake-server fixtures removed. The app is one Agent
  surface, one `ds4-agent` process; Metrics attributes the agent pid; the app
  delegate stops the agent on quit (no orphan).
- **Pool proven against the real engine**: a headless run sent a `PoolPrompt`
  (worker 1) while the engine was idle; worker 1 responded `"pong"`, and the
  stderr showed two session allocations (orchestrator + worker) in one process
  — the orchestrate-via-pool path is engine-verified, not just harness-tested.
- **Pool-state reset on restart** (this commit): `poolState`,
  `orchestrateWorkers`, `workerAnswers`, the watch task, and the in-flight
  worker bookkeeping are now cleared in `startAgent` — a restart mid-orchestrate
  no longer leaves a watch waiting on a dead engine's worker id.

- **Settings started**: Agent pane (shell toggle restored from the Agent tab;
  transcript font-size slider, 4 slots / default 16, live via an environment
  value + `MarkdownTheme.align`). `TranscriptFontScale` (5 tests).
- **Per-turn summary on the reply bubble** (the live status-bar rate stays;
  the finished turn's summary freezes under the bubble, DS4 stats-line
  precedent): `TurnSummary` (decode average via Δgenerated/Δts — `ts` is
  `CLOCK_MONOTONIC` ns, verified in the engine source), `StatusSnapshot`
  gained `generated`, transcript `.content` carries the summary
  (`attachSummary` guards trailing-content). 8 tests.

## Recorded follow-ups

- **Golden recapture queued** (ROADMAP Backlog): `golden-tools.ndjson`
  predates the wire's `kind` field, so the kind-driven card has no fixture
  test — only the live probe + engine C tests cover it.
- **Observed-once integration flake**: one run in five showed a single
  un-named test failure (tailed away before capture); four subsequent full
  runs were green. Not reproduced; recorded here rather than ignored.
- **Stable row IDs skipped by decision**: transcript `ForEach` remains
  offset-keyed (append-only today, no clear/reorder path); the array-keyed
  autoscroll fix (the streaming-freeze bug) IS in.
- **Receipts**: worker receipts render as quiet system rows (`send(_:asUser:)`),
  not user pills.
