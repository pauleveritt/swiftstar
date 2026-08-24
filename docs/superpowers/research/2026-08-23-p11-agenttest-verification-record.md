# P11 addendum — the canonical agent test: live run (2026-08-23)

**Status:** first live run, n=1, easy + hard spec, real engine (Laguna S 2.1).
The canonical agent test is now the project's reproducible headless proof that
the subagent machinery works end to end.

## Command

```bash
SWIFTSTAR_MODEL=<laguna-s-2.1 gguf> DS4_DIR=$PWD/external/ds4 \
  swift run swiftstar-agenttest --spec roadmap            # easy (imperative)
SWIFTSTAR_MODEL=<laguna-s-2.1 gguf> DS4_DIR=$PWD/external/ds4 \
  swift run swiftstar-agenttest --spec roadmap-user-story  # hard (user-story)
```

The harness decomposes the roadmap into its 3 phases, runs each as a subagent in
a chained-worktree transaction (`--subagent-pool 2`, one worker slot), and grades
the final candidate with the cumulative acceptance suite (`uv run pytest`).

## Result — easy (`roadmap.md`)

Three phases, each a candidate; the acceptance suite passed.

| Phase | Outcome | Mutations | Tokens |
|---|---|---|---|
| 1 (home page) | candidate | 5 | 486 |
| 2 (complaints board) | candidate | 4 | 287 |
| 3 (add complaint) | candidate | 4 | 309 |
| **Final** | candidate | — | — |
| **Acceptance** | **exit 0** (13 tests) | — | — |

## Result — hard (`roadmap-user-story.md`)

Phase 1 produced a candidate; Phase 2 returned a **`noChanges` receipt** — the
transaction stopped. This reproduces the recorded user-story finding: the
outcome-only spec does not trigger building, so the model declines to act.

| Phase | Outcome |
|---|---|
| 1 (welcoming front door) | candidate (6 mutations) |
| 2 (board where complaints are heard) | **receipt noChanges** |

## What this establishes (n=1)

- The harness drives the whole P11 path headlessly: decompose → handoff packet →
  chained worktrees → subagent turn → candidate ref → acceptance grade.
- The **easy** spec is winnable by the implementer model (3 phases, acceptance
  green) — the test is not a ceiling.
- The **hard** spec discriminates: it stops on the "no agency" failure, exactly
  the signal the local-ai-pi `user-story-arms.md` record predicted.

## What it does not establish

n=1, one model, no variance, no statistical claim. The DeepSeek qualitative
read ("does the code look good vs the spec") is wired as `GraderVerdict` but its
live invocation over the harness's *own* output is the next pass — this run's
deterministic acceptance suite is the grade.

## DeepSeek grader — demonstration

The grader prompt (rubric = `roadmap.md` + `mission.md` + `tech-stack.md`, plus
the generated code) was run against the **reference** implementation (known-good)
as a sanity check. `deepseek/deepseek-chat` returned:

```json
{"verdict":"good","reasons":["Correctly uses FastAPI as specified in the rubric",
  "Implements all three phases of the spec including home page, complaints board,
  and complaint submission", "Includes all required templates with proper Jinja2
  inheritance", "Properly handles form submission with redirect", "Includes seed
  complaints with the required 'Scope creep never ends.' text", ...]}
```

The grader parses into `GraderVerdict.parse(...) == .good`. Wiring this same
prompt over the harness's *own* output (via the code-dump the harness will write
before `discardFinal`) is the remaining grader step.

## Overnight session — grader end-to-end + n=4 variance (2026-08-23)

**Status:** the three overnight items are done to the extent the instrument
allows. The grader is wired and live; the re-runs and the n=4 batch exposed
that the instrument is **bimodal** — the model either works concisely or
thrashes in think mode to the 32k context limit — and that the DeepSeek grader
**does not discriminate** (it returns "good" for code the acceptance suite
rejects). Commit `accbea6`.

### 1. DeepSeek grader wired end-to-end

`Sources/swiftstar-agenttest/DeepSeekGrader.swift` builds the pinned prompt
(rubric = spec + `mission.md` + `tech-stack.md`, then the generated code), POSTs
`deepseek/deepseek-chat` over OpenRouter (timeout 120s + one retry), and parses
`GraderVerdict` fail-closed. The key comes from `OPENROUTER_API_KEY` or
`~/.pi/agent/auth.json` (`openrouter-curated`). `main.swift` dumps the final
worktree's code + rubric to the capture dir (`code.md`, `rubric.md`) **before
`discardFinal`**, calls the grader, and persists `verdict.json`.

Verified two ways: against the **reference** implementation (returns `good`,
the original demo), and against the harness's **own** output.

### 2. Re-run easy + hard (n=1) — corrected telemetry, and a grader blind spot

Easy (`roadmap.md`), one clean run, corrected telemetry (no tool/tool_request
double-count — the analyzer now reports tool-call count, rounds, re-reads,
repeated-identical):

| Phase | Outcome | Tool calls | Mutations | generated | ctx_pos | stop |
|---|---|---|---|---|---|---|
| 1 | candidate | 6 | 4 | 230 | 3242 | eos |
| 2 | candidate | 6 | 4 | 217 | 5743 | eos |
| 3 | candidate | 6 | 4 | 201 | 8112 | eos |
| **Acceptance** | **exit 1 — 12/13** | — | — | — | — | — |
| **Grader** | **good** | — | — | — | — | — |

18 tool calls, 0 re-reads, 0 repeated-identical, 86s. The one acceptance
failure: the model put the "Add Complaint" form inside the `{% block title %}`
of `complaints.html` instead of the content block, so it renders in the page
`<title>`. The grader still returned `good` — **the grader missed a
structural template bug the deterministic suite caught**.

Hard (`roadmap-user-story.md`) is **variable in its failure mode**, not the
single "noChanges" receipt of the first live run:

- Run A (pre-guard): phase 1 candidate with `stop=limit` (12,051 generated,
  ctx 32,767), then phase 2 died — the pooled worker session was full and could
  not compact (`not enough context left to request compaction summary`), and
  the harness crashed on `turnDidNotEnd`.
- Run B (post-guard): phase 1 `noChanges` receipt after a 28,580-token think
  thrash, clean stop.

Both runs discriminate (the hard spec never completes), but the mode varies.
The harness now stops the transaction cleanly when a phase ends
`limit`/`context_full` instead of reusing a full session and crashing the
engine.

### 3. The ~393 generatedTokens cap does not exist

Traced in the engine (`external/ds4/ds4_agent.c`): `n_predict` defaults to
**50000** (`-n` overrides); the per-turn budget is `min(n_predict,
ctx_room - 1)` at turn start; the stop reason is `context_full` (no room),
`limit` (budget hit), or `eos`. There is no 393 anywhere.

The `393/393/351` in the telemetry review was selection, not a cap. Real
per-phase generation is ~200–450 tokens when the model works concisely, and
**12k–31k** when it thrashes in think mode to the 32k context limit — think
tokens, not tool calls, dominate (one run generated 31,053 tokens with **zero**
tool calls).

### n=4 easy batch — the instrument is bimodal

`--batch N` runs the whole transaction N times in fresh repos and aggregates.
The easy n=4 (captures `20260823-20*roadmap-run*`):

| Run | Result | Phase 1 |
|---|---|---|
| 1 | **stopped** — `limit` | 31,053 gen, **0** tool calls, ~14 min |
| 2 | **stopped** — `limit` | 18,872 gen, 11 tool calls, ~15 min |
| 3 | completed | 3 phases eos, 29 calls, gen 447/386/526, ~9 min |
| 4 | killed (timeout) | still in phase 1 when the 40-min wall-clock timeout hit |

Run 3 — the only completion — **failed acceptance 7/13** (the route function
`def complaints(request)` shadowed the imported `complaints` list, breaking
`/complaints`), and the grader still returned `good`. So the grader's "green"
is not a pass signal: it returned `good` for 12/13, 7/13, and reference code
indiscriminately.

**The statistical claim is now negative and honest:** the easy spec does not
reliably win under the current instrument — ~1/4 runs complete and even those
fail acceptance — because the worker's unbounded think mode thrashes the 32k
context before it emits a tool call. The bounding prompt ("write once, do not
explore") does not bound thinking.

## Next

Companion analysis — a deeper read of the same captures, naming the think-loop
levers: `2026-08-23-p11-agenttest-laguna-hard-analysis.md`.

1. **Bound thinking.** The thrash is think-mode tokens, not tool calls — the
   companion analysis shows it is a degenerate loop (12–13 verbatim redrafts of
   the same solution). Levers, in order: a **facts-not-rules decision sheet** in
   the packet (pin where `complaints` lives, timestamp format, workspace-relative
   paths), a **think-token budget** engine-side, and a **self-test that sees the
   acceptance contract** (the vetted pytest should run `test_acceptance.py`, not
   the worker's own tests) — then re-run n=4.
2. **Re-scope the grader.** It says "good" for code the acceptance suite
   rejects (12/13 and 7/13). Either make the prompt force the grader to
   actually run/verify the routes, feed it the acceptance failures, or demote
   it to a supplementary signal and treat `uv run pytest` as the sole grade.
3. **n=4 hard** only after the think-thrash is bounded — at ~15 min per thrash
   run it is not worth batching until runs are cheap again.
