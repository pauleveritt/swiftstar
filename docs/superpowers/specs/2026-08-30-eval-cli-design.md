# Design: `swiftstar-eval`, one CLI for running and reading evals

**Status:** design, 2026-08-30. Supersedes the three-harness arrangement
(`swiftstar-agenttest`, `swiftstar-drive`, `swiftstar-analyze`) and absorbs
ROADMAP Backlog's "eval-system consolidation" plus P24's cleanup item (4).

## The failure this exists to prevent

On 2026-08-30 two `/chat` runs — `main` versus the P24.3 worktree — were read
first as a 2.2x speedup and then as sampling variance. **Both readings were
wrong**, and every error was an instrument defect rather than a judgement call:

1. `test`/`lint` were never advertised. Divergence #16 lived only in
   `agent_schemas_for`, which the DSML/DeepSeek prompt does not call, so the
   "treatment" arm had no treatment. Fixed as divergence #18 (engine
   `70400f5`) with a cross-family guard (`2a86c86`) pinning all four family
   builders to one tool set.
2. The arms differed by `--power 70` versus `100` — a setting recorded
   nowhere. Now in `provenance.md`, and drive takes `CAPTURE_POWER`
   (`1ea864d`).
3. "Generated tokens" was the wire's final segment, ~4x under. `TurnOutcome`
   now carries `generatedTokens`, `finalSegmentTokens`, `decodeTPS`
   (`93be29f`, `225776c`). This also fixed `WorktreeDispatch`'s turn-budget
   gate.
4. "Duration" was the wire span including pre-prompt time. `TurnSpan` and
   `analyze summary` now report the turn (`1fbebea`).

Four instrument defects; four fixes; **no mechanism that would have caught any
of them before the run**. That mechanism is what this design is.

## The three harnesses, and why none can answer "did this change help?"

- **`swiftstar-agenttest`** (1,397 lines) — env-driven
  (`SWIFTSTAR_VARIANT`/`SWIFTSTAR_MODEL`), hardwired to the orchestrator task,
  cannot run an ad-hoc prompt. Runs its own turn loop, so it uses neither
  `ToolRefusalTracker` nor `ToolCallBudgetTracker` — the two behavioral
  divergences P24's cleanup cycle owes a keep/drop/port decision on.
- **`swiftstar-drive`** (353 lines) — single-turn capture behind eight
  `CAPTURE_*` env knobs. Reproduces neither `/chat` nor `/quick`, because the
  turn loop that implements them lives in the app.
- **`swiftstar-analyze`** (768 lines) — post-hoc, ten verbs, and the strongest
  of the three. Its parsers are the production ones.

The structural cause is one fact: **the app's turn loop lives in
`Sources/SwiftStar/AgentController.swift`, a 66 KB SwiftUI type neither runner
can link.** `SwiftStarKit`'s `AgentCommand` gives argv and environment but not
the loop, so each runner re-implements it and each drifts. `BRIEF.md` already
specifies `SwiftStar` as "thin, because the decisions live in Kit"; a
controller owning the turn loop is drift from the settled architecture, not
new scope.

## What we are building

One executable, `swiftstar-eval`, that runs the orchestrator eval, an ad-hoc
prompt, a `/chat` or a `/quick` **through the same spawn path the app uses**,
and hands every result to the same analyzer.

### Four components

**`AgentSession`** — `SwiftStarAppKit`, SwiftUI-free. Spawn, the wire loop,
the tool-callback loop, capture and provenance writing, interrupt, stop.
Extracted from `AgentController`'s `startAgent` / `consumeWire` /
`consumeStderr` / `send` / `writeToolResult` / `interrupt` / `stopAgent`
seam plus the `orchestrate` / `quick` / `consult` entry points. Transcript
rows, bubbles, tool cards, memory polling and the `@Observable` surface stay
in the app; `AgentController` becomes a wrapper that owns view state and
forwards. **The guarantee: a divergence between what the app runs and what an
eval runs stops compiling.**

**`EvalExperiment`** — `SwiftStarKit`, pure. Parses the experiment file,
resolves each arm to a `SpawnRecord`, computes the arm-to-arm diff, refuses
undeclared differences, emits the interleaved run order. No I/O, so it is
fast-tier.

**`SpawnRecord`** — `SwiftStarKit`, pure value type. The complete, resolved
description of one spawn: argv, engine submodule SHA, gguf path and size,
variant contract, sampler, power, think policy, advertised tool set,
workspace, shell posture, host-tools posture, macOS build, wired limit. It is
what `provenance.md` renders and what the arm diff compares. **A setting that
is not in `SpawnRecord` is a setting that can silently differ between arms**,
which is defect 2 above.

**`EvalReport`** — `SwiftStarKit`, pure. Per-pair Sigma-suffix deltas, the
spread across pairs, the falsifier verdict, the claim stamp. Analyzer output
in, text out.

### Verbs

`run` (one arm: ad-hoc, or `/chat` / `/quick` / `/orchestrate` routed through
the existing `CommandRouter`), `experiment` (the paired, interleaved thing),
and the ten analyzer verbs kept at top level under their current names —
`list`, `summary`, `trace`, `diff`, `rereads`, `findings`, `taxonomy`,
`validate`, `report`, `index` — so existing docs and habits survive the move.

### Environment knobs die

Every `CAPTURE_*` and `SWIFTSTAR_*` variable becomes a flag or an
experiment-file key. **A setting that lives in an environment variable is a
setting that lands in no provenance**, which is how `--power 70` versus `100`
got lost. `DS4_DIR` survives as the one exception, because `BRIEF.md` binding
rule 7 gives it a defined role in pointing the app at any engine build.

## The experiment file

Experiment definitions live in `evals/<name>.json`, committed **before** the
run. Results land in `captures/eval/<name>/<timestamp>/`.

This relocates P24.3 Task 12's `Tools/p24-3-measurement/`: one home for every
experiment beats one directory per phase. The relocation is recorded in that
plan's Result section rather than done silently.

```json
{ "name": "p24-3-run-digest-family",
  "question": "Do host-owned test/lint reduce Sigma-suffix on a change-and-verify turn?",
  "falsifier": "the digest drops something decision-relevant",
  "variable": "tools",
  "pairs": 3,
  "mode": "chat",
  "promptFile": "evals/p24-3-prompt.md",
  "captureSelection": "recordsWork",
  "arms": [ {"id": "control",   "tools": ["read","write","list","search","bash"]},
            {"id": "treatment", "tools": ["read","write","list","search","bash","test","lint"]} ],
  "common": { "gitRef": "p24-3-run-digest-family", "variant": "deepseek-v4-flash",
              "ctx": 50000, "power": 70, "shell": "on", "hostTools": true } }
```

`question` and `falsifier` are the pre-registration. They are copied verbatim
into the results directory before the first spawn, so the artifact carries
them rather than someone's memory.

`captureSelection` names the rule for which captures count. It defaults to
`recordsWork` (`CaptureUsability.recordsWork`) and **never** "completed turn"
— the non-carryover P24.3's Task 12 protocol already records.

An arm may pin any axis: `gitRef`, `variant`, `model`, `ctx`, `power`,
`shell`, `workspace`, `hostTools`, `tools`, `thinkPolicy`, `maxTokens`,
`seed`. `common` applies to every arm; an arm's own keys override it.

`variable` names **exactly one** key. A multi-factor experiment is refused
rather than run — two axes at once is what produced the 2026-08-30 misreading,
and a tool that permits it inherits the defect. Vary one axis, or write two
experiments.

`mode` is one of `bare` (a prompt with no leading slash — the default agent
mode), `chat`, `quick`, or `orchestrate`, parsed by the same `CommandRouter`
the app's composer uses.

## The arm diff is a refusal, not a report

Before spawning anything, each arm resolves to a full `SpawnRecord`. The set
of keys that differ between arms must be a subset of

    {the key named by `variable`} ∪ {capture directory, wall-clock, run index}

and anything else aborts, naming the offending keys and both values. That
second set is the **must-differ allowlist**; it is fixed in code, not
configurable, because an experiment that can widen its own allowlist has no
guard at all.

`--power 70` versus `100` would have been caught here before a single token
was generated.

**When `variable` is `gitRef`**, the engine submodule SHA and the built binary
are *expected* to differ, and the diff admits exactly those two keys in
addition — because they are downstream of the declared variable. Every other
key still binds. This is the axis the 2026-08-30 failure varied, and it is
therefore the one the tool must support natively rather than leave to a manual
two-run comparison.

## Repeats, interleaving, and how strong a claim is allowed

`n=1` per arm cannot support a causal claim, so interleaved repeats are the
default rather than an option.

- **ABBA per pair, minimum 3 pairs.** `pairs` may be raised in the file, never
  lowered below 3.
- **Both arms within a pair share a pinned seed**, so a pair is seed-matched
  and its delta is not reading sampling noise on one axis. Seeds do not
  guarantee identical trajectories once contexts diverge; they remove one
  variance source at no cost, and the report says so rather than implying more.
- **No headline ratio.** The report prints each pair's delta and the spread
  across pairs. It does not print a single "N times faster" number — the exact
  artifact misread twice on 2026-08-30. A computed effect size (median ratio
  with a nonparametric interval) is deliberately **out of scope**: it is the
  number most likely to be quoted without its interval.
- **Raising `n` after seeing results** means a new file with a new name, which
  git records. The CLI refuses to extend an experiment whose results directory
  already exists.
- **`--exploratory`** allows `n=1` and stamps every output line
  `NOT A CAUSAL CLAIM`.

**The falsifier is answered or the run has no verdict.** Where the verdict is a
human judgement — P24.3's "the digest drops nothing decision-relevant" is one —
the CLI writes `VERDICT: unrecorded` and exits non-zero until someone records
it. No run produces a PASS by default. Where it is machine-checkable, the CLI
computes it and records the computation.

**Grader output is never the primary metric.** `DeepSeekGrader` moves in still
marked advisory pending calibration (P26 item 4). It is reported beside the
paired bill, never as it.

## Results layout

    captures/eval/<name>/<timestamp>/
      experiment.json      frozen copy of the definition as run
      preregistration.md   question + falsifier, written before the first spawn
      arm-diff.txt         the resolved SpawnRecord diff that was admitted
      pair-1/control/      a capture tree (wire, trace, stderr, provenance.md)
      pair-1/treatment/
      ...
      report.md            per-pair deltas, spread, falsifier verdict

Every capture tree is the format `CaptureWriter` already writes, so every
analyzer verb works on it unchanged. **Binding rule 5 holds**: the capture is
written to disk before anything reads it, and the analyzer runs against the
artifact.

## Two cycles

**Cycle 1 — the CLI and the first bill.** The `AgentSession` extraction (its
own task, landing with the app's tests green before anything is built on it),
the CLI skeleton, `SpawnRecord`, `EvalExperiment`, `EvalReport`, the analyzer
verbs moved in, and P24.3 Task 12's pre-registered paired bill run on a
change-and-verify prompt that actually needs `test`/`lint` — not a code-reading
Q&A. `swiftstar-drive` and `swiftstar-analyze` are deleted at the end of it.

**Cycle 2 — absorbing the orchestrator eval.** The orchestrator becomes
`swiftstar-eval run --mode orchestrate --spec roadmap`, driving `AgentSession`.
`RepairLoop`, `PhaseRepair`, `Decompose`, `TextContractHarvest` and
`AcceptanceGrader` are reused unchanged; what dies is `agenttest/main.swift`'s
env-knob plumbing and its private loop. `run-config.json` is replaced by the
same `provenance.md` plus `SpawnRecord` every other run writes.

**Cycle 2 closes P24's cleanup item (4).** Verified 2026-08-30:
`ToolRefusalTracker` and `ToolCallBudgetTracker` (`14bbe70`, `29d2d4b`) unify
the app and the pool — `AgentController` and `PoolOrchestrator` both use them —
and `swiftstar-agenttest` uses neither. Porting agenttest onto `AgentSession`
is what retires the refusal-streak and `toolCallBudget` divergences: they stop
being a keep/drop/port question and become "whatever the product does," by
construction. Two roadmap items describe one piece of work; the ROADMAP row
should say so.

## Testing

Tiers per `BRIEF.md`, unchanged by any of this.

- **Fast.** `EvalExperiment`, `EvalReport`, `SpawnRecord` and its diff are
  pure, tested against fixture experiment files. **Binding rule 4**: the
  refusal tests (an arm pair differing on an undeclared key; `pairs: 1` without
  `--exploratory`; a results directory that already exists) each get a sibling
  success test. **Binding rule 6**: the diff names the fixture experiment it
  admitted and the one it refused.
- **Integration.** `AgentSession` against the fake engine binaries generated
  from committed captures. The extraction's own proof is that the app's
  existing integration tests stay green while the loop moves.
- **Live.** `experiment` only. Never in CI.

**Binding rule 2** applies to every new test: break it, watch it fail, restore.

## Out of scope

- A computed effect size or significance test (above).
- Re-litigating `swiftstar-analyze`'s verb semantics. They move as they are.
- `DeepSeekGrader` calibration — Backlog, and its absence is why grader output
  stays advisory here.
- The nine closed-phase plans currently failing `just lint-docs` (P19.1, P22,
  P23 x2, P26, P24.1 x2, P24.2, P24.3 all exceed the 400-line / 25%-fenced
  caps). Pre-existing debt from closes that skipped the fence-to-`path:line`
  step; noted 2026-08-30, owed by a separate cleanup, not folded in here.

## Amendments this design owes

**The DSML reversal.** P24.3's plan records "the DSML/DeepSeek block is
untouched (the `dispatch` precedent)" at lines 25, 1398, 1405, the fork-ledger
row 15, and the self-review at 1550. That decision is what made divergence #16
unreachable for the model SwiftStar ships, and it was reversed in the engine
(#18, plus the cross-family guard) without being written back. Per
`docs/sdd.md`'s "kept as it was written," the reversal is recorded **beside**
the original as a dated note, not edited over it: the `dispatch` precedent was
applied to a tool the shipped model needs, and a schema the shipped prompt
never builds is not a schema.

**ROADMAP.** One row for the eval CLI, absorbing the Backlog's "eval-system
consolidation" entry and P24's item (4), with both pointing at it rather than
restating it.

## Risks

- **The extraction is the risk.** `AgentController` is 66 KB and the loop is
  entangled with view state. Mitigation: it is its own task, gated on the
  app's existing tests staying green, before any CLI code is written.
- **`2a86c86` is not pushed.** The cross-family guard exists only in local
  submodule checkouts; a fresh clone cannot build the treatment arm. Push
  before the bill is run, or the artifact is unreproducible.
- **The arm diff can only refuse what `SpawnRecord` models.** A setting the
  engine reads that we never record is invisible to it. Mitigation: the record
  is built from `AgentCommand.argv` plus the resolved environment, so a new
  engine flag that the app passes is in the record by construction; one the
  app does not pass is not an arm axis.
