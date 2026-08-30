# P24.1 window-honoring reads — the "after" measurement (2026-08-30)

**Status: NOT MEASURED. The cycle's code is implemented and unit-tested; its
live claim is unverified.** This note records a failed measurement attempt and
the blocker, because the pre-registered falsifier must be answered either way —
including with "the instrument cannot see the thing."

## What was attempted

A scripted read-heavy session in the 1809 shape via the committed live-capture
program (`just capture` → `swiftstar-drive`): 12 prompts forcing repeated work
on files over 8000 bytes (`AgentView.swift` 21,603 B, `AgentController.swift`
67,379 B, `ROADMAP.md` 106,149 B) in an isolated workspace, `-c 32768`, real
engine, real model (`laguna-s-2.1-RoutedQ2_K-Last27Q3_K`).

Ran clean in 8 minutes (14:32:38 → 14:40:38), capture at
`captures/20260830-103238-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`.

## Why it measures nothing

**`swiftstar-drive` has no host-tool loop.** It never passes `--host-tools`
(its argv is the P5 capture shape, `Sources/swiftstar-drive/main.swift:129-165`)
and contains zero references to `ToolCallbackResponder`, `HostToolExecutor`, or
`tool_result`. So the *engine* ran `read` itself, through
`agent_read_range` (`ds4_agent.c:8102`) — which already honored
`start_line`/`max_lines` before this cycle and is not the code P24.1 changed.

The wire proves it:

```
tool_request events, new capture:      0
tool_request events, 1809 baseline:  119
```

`tool_request` is the event emitted only when the engine delegates a tool to the
host. The new capture has 103 `tool` events (engine-side execution) and no
delegation at all. `HostToolExecutor.readResult` — the function this cycle
rewrote — was never called.

Reporting the resulting window distribution as a pass would have been the
harness-not-the-model trap for the fourth time (`ROADMAP.md:15`): a clean number
measured off the code under test.

## The falsifier, unanswered

The pre-registered failure condition stands unevaluated:

> many distinct windows clustered on one region of one file

The detector for it is built and **validated against the 1809 baseline**, where
it correctly reproduces the spec's Problem table — 22 distinct windows over 32
calls on `AgentView.swift`, 10 over 11 on `ROADMAP.md`, both tripping. It is
ready to run against a capture that exercises the host path.

## What would unblock this

Only two routes reach `HostToolExecutor`:

1. **The app** (`AgentController`), which always passes `--host-tools`
   (`AgentCommand.swift:105-113`). This is the faithful reproduction — the 1809
   baseline came from here — but it is a SwiftUI app with no scripted driver.
2. **`swiftstar-agenttest`/`PoolOrchestrator`**, which does implement the host
   loop. Rejected for this measurement on two grounds: its orchestrator carries
   a refusal-streak corrective the app does not
   (`PoolOrchestrator.swift:142-156`), which confounds a read-behavior
   comparison; and the fourth campaign arm is still unrun, so the instrument
   should not be exercised mid-campaign.

**Recommended:** give `swiftstar-drive` a host-tool loop (`--host-tools` plus a
`ToolCallbackResponder` + `HostToolExecutor` pair, which already exist and are
pure) so the committed capture program can drive the path the app actually uses.
That is a small, self-contained cycle, and it is a gap worth closing regardless
of P24.1: **today no committed tool can capture the app's real tool path**,
which is why the 1809 baseline had to come from a hand-driven session.

## Static evidence that does hold

Not a substitute for the live run, but recorded because it is checkable:

- **The 1809 counterfactual's premise.** `bottomStatusBar` — the content the
  1809 session spent 32 reads failing to reach — is defined at
  `Sources/SwiftStar/AgentView.swift:261`, inside a
  `start_line=252, max_lines=80` window. That window renders to **4,484 bytes**,
  under both the 7000-byte budget and the 8000-byte condenser cap, so it arrives
  whole. One read now delivers what 32 could not.
- **The invariant is unit-pinned.** `ReadWindowTests` (20 tests) includes
  `aRenderedWindowSurvivesTheCondenserUnchanged` — the test whose absence let the
  withdrawn design ship a false premise — plus
  `headerRangeAlwaysNamesExactlyTheLinesInTheBody`.
- **The executor path is integration-pinned.** `HostToolExecutorTests` (22
  tests) covers window honoring, `more` continuation across the seam, EOF
  clearing the continuation, and per-workspace-root keying.

## Status

The spec stays `proposed`. P24.1's code is complete and green (790 tests); its
**live claim is unverified and must not be reported as measured** until a
capture exists that contains `tool_request` events.
