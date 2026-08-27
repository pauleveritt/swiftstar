# Heavy-session telemetry findings (2026-08-26)

*Analyzed from the live capture `captures/live/20260826-210926/` (the first
app session that produced on-disk telemetry — trace only; the wire tee had a
`FileHandle(forWritingAtPath:)` bug, fixed in `4e7cb3a`). Second session
`20260826-214304` added the orchestrate hang. These findings motivated the
ctx-50k default, the shell-on lever, and the dispatch-preference rule.*

## The session

8 user prompts, in order: count swift files / how many have a struct / any
observables / bindables / access to Superpowers / find the roadmap / access to
Context7 / "spike in a worktree to update this project to the latest SwiftUI
standards". **73 tool rounds** across the 8 prompts; max transcript 27,123
tokens. Tool surface: `read`/`list`/`search`/`glob` loops only — **no `bash`**
(shell off by default).

## Two compactions at 89% of context

```
21:16:38 compacted reason="soft limit before tool continuation"
         old=29,136 new=5,010 tail_start=25,860 tail=3,276
21:21:41 compacted reason="soft limit before tool continuation"
         old=28,695 new=5,392 tail_start=25,419 tail=3,276
```

Twice, the transcript hit 89% of the 32,768 window and the engine dropped
~24k tokens of accumulated context — the agent forgot most of what it had
learned mid-session, then re-learned it. This is the "it feels degraded"
mechanism, measured.

## The degradation curve (the P11 curve, live)

Effective prefill throughput (`suffix tokens / prefill ms`) within one prompt's
rounds as context grew 12k → 27k:

| ctx | prefill ms | eff tok/s |
|---|---|---|
| 12,459 | 2,044 | 231.5 |
| 19,151 | 9,741 | 194.4 |
| 23,101 | 4,303 | 147.3 |
| 27,123 | 3,760 | 134.3 |

The suffix per round stayed ~1,700–1,900 tokens, yet prefill time roughly
doubled (2,044 → 11,557 ms) as context filled — same work, ~2× the wall-clock,
purely from depth. Decode was never the bottleneck (tool-start → done gaps
~0.6–2s).

## The architecture win, visible

85–95% of every round's prompt served from KV cache (`cached/prompt` per
round: 1,179/1,243 → 10,740/12,670) — the persistent-session economy the pool
is built on. The cost is not recomputation; it is the depth-scaled prefill
tail + the compaction cliff.

## The tool-surface finding

"Count how many swift files" took **23+ read/search rounds** — because `bash`
was excluded from the tool schema (deny posture), the model substituted
reasoning-driven reads for a one-line `find | wc -l`. The follow-up spike run
with `--shell on` (see `2026-08-26-spike-shell-on-findings.md`) confirmed the
lever: the same class of task became a real git/grep/build worktree spike.

## The orchestrate-session hang (214304)

`/orchestrate` (then `dispatchAttempt`-based) spawned a **second full 48 GB
model process**; that worker sat at 0% CPU, ~4s of CPU total over 4.7 min,
blocked before generating (the first-`ready`-sends-the-prompt handshake never
completed). Routing orchestrate through the pool (`00b5d80`) removed the
second process and the hang class; the pool protocol was then verified against
the real engine (worker prompt → `pong`, two sessions in one process).

## What this schedules

- ctx default 32,768 → 51,200 (the compaction cliff moves; 42k hit 83% of 50k
  with no compaction).
- The shell lever (Settings toggle) — the single biggest round-trip reducer.
- The dispatch-preference bootstrap rule (P20): exploration belongs in a
  worker, not the main context.
- Re-anchor the severity thresholds (P21): `DialLogic` warning=37.5k /
  critical=75k is anchored at 150k context — at 32k the context ring never
  fired, even at 89% full.
