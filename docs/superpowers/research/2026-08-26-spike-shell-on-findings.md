# Spike prompt, shell-on — telemetry findings

*Measured 2026-08-26 headless against the real engine (Laguna S 2.1 Routed
Q2/Q3, 48 GB) with the then-landed fixes: `--subagent-pool 2`, `-c 51200`,
`--shell on`, `--seed 42`, `-n 2048`, 480 s wall. Capture at
`/tmp/spike-run/` (wire + trace + stderr). Single run — directional, not a
rate (the `/goal` v5 noise caveat applies).*

## Prompt

> I would like to do a spike in a worktree to see about updating this project
> to the latest and greatest SwiftUI standards and frameworks

## What the shell lever changed

With `--shell on`, the agent ran a **genuine spike** — the bash commands
(verbatim from the wire) show the full loop the prompt asked for:

1. `git log --oneline -15`
2. `swift --version`
3. `grep -n '@Observable\|class.*Controller\|@MainActor' EngineController.swift AgentController.swift MetricsModel.swift DiagnosticsModel.swift`
4. `git remote -v`
5. `git worktree add -b spike-swiftui-standards ../spike-swiftui-standards`
6. `cd spike-swiftui-standards && swift build 2>&1 | tail -20`

The earlier shell-off session (capture `20260826-210926`) did read/search
loops and never created a worktree or ran a build. The deny posture was the
capability ceiling, not the model.

## Where the tokens went

- Tool mix: **bash 6**, read 20, list 5 — bash is the minority but does the
  irreplaceable work (worktree, build, grep).
- **think 1,232 events vs text 107** — think=high spent ~11× more on reasoning
  than on answering. The largest token cost, and a config choice.

## The degradation curve, quantified

Effective prefill throughput (`suffix tokens / prefill ms`) by context depth:

| round | ctx | suffix | tok/s |
|---|---|---|---|
| r2 | 9,147 | 7,615 | ~430 |
| r9 | 30,456 | 5,214 | ~157 |
| r14 | 42,419 | 483 | ~74 |

Same-size work ~2.7× slower at depth — r9's suffix is *smaller* than r2's yet
took 2× the wall-clock. Peak prefill 33.3 s (a big file read at ctx 30k).
**No compaction** at 42k/51k (83%) — the 50k ctx moved the cliff; the
"compaction" grep hits were token text, not events.

## Levers this points at

1. `--nothink` (the queued quick-reply mode) collapses the 11× think budget.
2. The prefill tax is file-read-driven → the "don't-re-read" + warm-prefix
   routing backlog entries.
3. A spike's exploration belongs in a shallow worker (the small-ctx worker
   backlog entry), keeping deep prefill out of the main context.

## Coincidence

The agent read `ChatView.swift`/`EngineController.swift` to assess their
SwiftUI patterns — the same surface retired hours later (`f546671`). The spike
independently reached for the surface that is now gone.
