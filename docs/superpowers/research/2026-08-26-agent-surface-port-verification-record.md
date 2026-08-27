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
