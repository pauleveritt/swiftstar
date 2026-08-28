# The 1809 prefill-tail findings (2026-08-27)

*Analyzed from the live capture `captures/live/20260827-200648/` (the app's
agent session that produced the P21 telemetry fixes on this date: the lossy
trace read `3611d96` and the outcome alignment `ef59035`). Read with the
production parsers via `swift run swiftstar-analyze` (`summary`/`trace`), raw
NDJSON only where the CLI does not answer. Confirms and sharpens the
2026-08-26 heavy-session findings: the same depth-scaled prefill tail, now
pinned to a single recurring culprit.*

## The session

Laguna XS 2.1 (`laguna-xs-2.1-RoutedQ3_K-biased.gguf`), M5 Max 128 GiB, ctx
32,768, `20:06:48` → ~`20:34:24` EDT (~28 min). Four turns — three
user-visible plus the consult turn (worker 1):

| turn | task | tools | generated (accumulator) | stop |
|---|---|---|---|---|
| 1 | (startup system-prompt prefill) | 0 | 0 | — |
| 2 | "Take a look in this project." | 62 (list 26, read 34, search 2) | 3,819 | interrupt |
| 3 | "What would it take to put the current memory usage of all parts of a running SwiftStar app…" | 55 (read 39, list 6, search 5, grep 2, more 2, shell 1) | 4,104 | interrupt |
| 4 | consult: "Python is a high-level…" (dispatched to worker 1, surfaced as "→ consulted: …") | 1 | 125 | interrupt |

Zero mutations, zero status errors, zero throttle (power always 100). The
worker-1 consult itself generated 18 tokens and ended `eos` in its own small
context; the orchestrator's consult turn (above) is the turn that dispatched
it and surfaced the answer.

## Finding 1 — the 1809-tax: one file re-read 31 times is 37% of all prefill

- **30 prefill syncs with suffix exactly `1809` tokens** — 54,270 tokens =
  37.5% of the session's entire Σsuffix (144,631), 5.7 of the 12.7 prefill
  minutes (each sync 5.9–15.6 s).
- The top three repeated suffixes (1809×29, 2276×9, 1956×4) = **57% of all
  suffix work** (7.5 min).
- The 1809 syncs correlate tightly with **31 reads of
  `Sources/SwiftStar/AgentView.swift`** (427 lines; 27 of the reads fall
  inside the 1809 windows — full-file and overlapping window reads such as
  250–350, 252–332). A full read of that file ≈ 1,793 tokens at ~4.2
  tok/line, consistent with the 1,809 read result being the re-prefixed
  working tail.

## Finding 2 — compaction churn drives the re-reads

Five compactions in ~24 min, all `soft limit before tool continuation` at
~28–29k → ~5k, each discarding ~23k tokens of context:

```
20:10:06  29331 -> 5063
20:16:03  28638 -> 5189
20:21:50  28974 -> 5324
20:25:30  28708 -> 5073
20:29:18  28073 -> 5081
```

The agent re-reads files after each compaction to recover what the cliff
discarded — every recovery is one more 1809 sync.

## Finding 3 — prefill rate collapses with depth (the multiplier)

Effective prefill throughput by context depth (median, from the wire's
`prefill_tps`):

| ctx | tok/s |
|---|---|
| 0–5k | 519.6 |
| 5–10k | 251.2 |
| 10–15k | 166.6 |
| 15–20k | 136.6 |
| 20–25k | 125.6 |
| 25–30k | 113.7 |

**4.6× slower at 25–30k than fresh.** That is why the same 1,809 tokens cost
5.9 s early in the session and 15.6 s at depth. Decode degrades far less
(46 → 38 tok/s, ~20%).

## Finding 4 — the prefix cache is healthy; the tax is the tails

Per-sync `cached/prompt`: median 0.93, mean 0.88. KV reuse is not the
problem — the repeated 1,809-token tails are. This is the "sum of prefill
tails, each taxed by depth" enemy from the 2026-08-26 findings, now measured
with a named culprit instead of a diffuse curve.

## Finding 5 — harness machinery use: near-zero, and correctly so

- **Worker split:** worker 0 (orchestrator) 5,635 events; worker 1 exactly
  14 — a single pool consult at 20:34:22 (the P22.2 `isConsult` path: worker
  answered "Python is a high-level…" in 18 tokens, surfaced as
  `→ consulted: …`). The pool machinery worked for its designed case.
- **No worktree dispatch:** 0 mutations, `validationRan: false` on all three
  outcomes — no handoff packets, no `WorktreeDispatch`, no revision checks,
  no candidate refs. Correct: worktree isolation exists to make *writes*
  safe; this session never wrote.
- **No subagent delegation of the two exploration turns:** also correct. Both
  were user-steered (watched live, interrupted twice) and open-ended with no
  machine-checkable acceptance predicate — P10's own routing rule says such
  tasks are *not* delegable, and the dispatch-preference bootstrap rule must
  not fire for them.
- **Host-tools path exercised throughout:** 118 `tool_request` events (the
  P9/P15 host-owned executor ran every `read`/`list`/`search`/`grep`/`shell`,
  including the one shell call: `wc -l …/AgentView.swift`). This is the
  substrate the read-guard depends on.

## What this schedules

1. **P24 absorbs the read-guard (`don't-re-read`).** The Context-economy
   backlog entry's reopen condition ("reopens with P9 — the host must own
   tool results to substitute them") is satisfied: P9's host tools shipped
   and this capture measured the win. `don't-re-read` (hash+mtime every
   file; answer an unchanged re-read "unchanged since turn N" instead of
   contents) is itself a deterministic host-owned tool — P24's definition —
   and the direct fix for Finding 1. P24's acceptance: the paired-bill
   `swiftstar-analyze diff` guardrail on a real session, not self-reported
   savings.
2. **Deterministic compaction skeleton — reopen condition FIRED.** The
   backlog entry reopens "when a compaction is actually observed at the
   everyday context size and its measured cost … justifies the fork": five
   compactions in 24 minutes at 28–29k, each discarding ~23k tokens.
   Still needs the `ds4_agent.c` fork; sequence after P24.
3. **`recall` tool — reopen condition FIRED.** A compaction was observed
   discarding something a later turn needed (the post-compaction
   AgentView.swift re-reads). P9 also landed, so the app-side form is
   available. Sequence after P24.
4. **Dispatch-preference negative data point (P20).** The two exploration
   turns were interactive, user-watched, interrupted, open-ended — the
   dispatch-preference rule must exclude watched interactive sessions; the
   pool consult was the right (and only) delegation, and it worked.
5. **DumbImplementer eval (P21 forward) unchanged in shape** — this capture
   re-confirms the Σsuffix design (Σprompt double-counts; only Σsuffix is
   additively meaningful; the paired-bill diff is the guardrail).
