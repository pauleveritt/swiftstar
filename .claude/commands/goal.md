# /goal — one iteration of a pre-registered experiment

You are one iteration of a loop that **runs to completion without stopping for
the human**. Do one unit of work, write it to the ledger, commit, and continue.
The loop's memory is the ledger, not your context.

> **v4, 2026-08-26.** v1–v3 ran 21 iterations across two ledgers. They landed
> real harness fixes and never once satisfied a single done-when clause. The
> defect-discovery rate stayed flat at ~0.8 new defects per iteration for all 21
> — there was never evidence that "one more fix" converges. v3 escalated to the
> human in 4 of its 8 iterations.
>
> v3's text is in git at `fadd48e`. Both old ledgers are closed records.

## Why v3 was replaced — three provable faults, not a change of taste

- **Clause (c)** (byte-identical packets at the same seed) **was refuted by the
  loop's own iteration 6**: seed forwarded (verified from live argv), identical
  prompt sha, identical prefill length, same pool worker — different output on
  turn 1. A round-N packet embeds round-(N−1)'s non-deterministic model output,
  so no harness change can ever satisfy it for rounds ≥ 2. **The loop proved its
  own goal impossible and kept running under it.**
- **Clause (d)** (every check fires on a known-bad from the current batch) is
  **anti-convergent**: the checks detect harness defects, the defects are being
  fixed, so a batch from a *working* harness contains no known-bads. (d) becomes
  unsatisfiable exactly when the apparatus succeeds. With (a) it demanded a batch
  that fails in all known ways and no unknown way.
- **Clause (a)** (zero cells fail in an uncovered way) is a completeness claim
  over an open failure space: falsifiable, never verifiable, cannot accumulate.

And the structural cause of the whack-a-mole: validity was **conjunctive over a
long serial pipeline**, so each fix advanced the frontier exactly one link to
where the next defect waited — while a weak model acted as a fuzzer, exercising
harness paths no test author anticipated. Fuzzing finds bugs for as long as you
run it.

Meanwhile the [80-cell verdict](../../docs/superpowers/research/2026-08-26-overnight-80-cell-verdict.md)
had already named the cheap decisive test in §5 and open-work item 9: **a
multi-file repair fixture**. Twenty-one iterations later it had never been built.
It exists now (`fixtures/agenttest/repair/README-multifile.md`).

## The goal

> **Answer the original question: is Mellum's multi-file repair failure a
> BUDGET limit, a FRAMING limit, or a DEPTH limit?**
>
> **Done when** every row of the pre-registered manifest
> `docs/superpowers/research/experiment-manifest.tsv` (**24 cells** — 4 fixtures
> × 2 budgets × 3 seeds) has a recorded outcome, `harness-void` ≤ 20% of cells
> (≤ 4), and a dated verdict document in `docs/superpowers/research/` states the
> answer per arm with the numbers quoted.

"Done" is **manifest completeness** — a closed, mechanical predicate you can
evaluate with `wc -l`. It cannot be reset by a new discovery, and a harness
defect no longer voids the experiment: it becomes a recorded row.

**The three arms.** Depth: `plausible-wrong-fix` (1 file) → `depth-2` → `depth-3`,
all keeping the suite importable so every defect is visible from round 1. Budget:
the same fixtures at `AGENTTEST_REPAIR_ROUNDS` ∈ {2, 5}, comparable because the
starting tree is **pinned by a commit** — the confound that made v2's budget
comparison worthless is gone by construction. Framing: `framing-2` shows a
precondition manifest where `depth-2` shows failing assertions.

**The narrowness this buys, stated up front and repeated in the verdict:** this
measures repair **in isolation from a pinned tree**, not repair in the pipeline.
It is the only version comparable across budgets. The verdict must not
generalise to pipeline behaviour.

If `ROADMAP.md`'s `## Now` stops naming this experiment, stop and tell the human.

## Pre-authorised policy — the loop decides, and records

Ratified once at adoption. This **replaces v3's "escalate on measurement
semantics"**, which in a measurement project meant escalating on nearly
everything.

| situation | what the loop does, without asking |
|---|---|
| a harness defect voids a cell | record `harness-void: <cause>`, move to the next row |
| one cause voids ≥3 cells or >20% so far | spend ONE iteration fixing that single cause, then re-run **only the voided cells** — never re-run a recorded cell |
| model-vs-harness attribution genuinely ambiguous | default to **model**, set `disputed`; disputed cells are a separate line in the verdict |
| runaway generation / `limit` stop | a **model-behaviour observation** on that cell ("ran away at N tokens, ctx used M of 32768"), not a validity question. The cell counts. |
| failure class mislabelled (`validationFailed` vs `contractNotFollowed`) | record both labels in the row; never reclassify mid-experiment |
| run-to-run non-determinism | a measured variable across the 3 seeds; never a blocker, never a defect |
| engine busy (`ps aux` for `llama\|agenttest\|ds4-agent`) | record `deferred: engine busy`, do non-GPU work or stop for the session |

**The question queue.** Anything that would once have escalated gets a paragraph
appended to `docs/superpowers/research/questions.md`: the question, the default
taken, and which cells carry `disputed`. The human drains it whenever they like.
Every cell keeps its raw capture, so an answer can flip flagged cells
retroactively at **zero GPU cost**. Escalation becomes asynchronous, not blocking.

**Budgets that guarantee termination.** 15 iterations, ~4 GPU-hours. Hitting a
ceiling does not fail the loop — it produces the verdict from completed cells
with `n` stated honestly. A partial answer with honest `n` is an answer.

## Validity — two checks, not seven

Fixture tier collapses the burden: the starting tree is committed (no build
phase, so no missing-file storms), there are no phase briefs and no verdict
grader (the grade is pytest's exit and failure count, mechanical). Surviving:

- **delivered** — `wire.ndjson` shows no `exceeds context`, no `turnDidNotEnd`,
  no `limit`/`contextFull` stop. (v3's `check_v5`, unchanged.)
- **harvest-faithful** — no heading had fenced code discarded in favour of
  commentary. (v3's widened `check_v6`, unchanged.)

A cell failing either is `harness-void`, recorded, and the loop continues.

Retained dormant for any future pipeline work, not in this gate: `check_v1`,
`check_v2`, `check_v3`, `check_v4` and their fixtures. **Deleted outright:** V7
as an invariant and the ruling behind it — the loop's own iteration 6 refuted
it, and a check for a property the engine cannot deliver is a check that can
only ever report failure. `MachineEvidence.normalizingEphemera` stays: it is a
prompt-caching and cleanliness win regardless.

**Do not re-audit the historical captures.** The 80-cell matrix and both n=4
batches are harness archaeology, not model data. Both ledgers are closed. **No
number from them appears in this verdict.**

## Three actions, not five

1. **run** — execute the next incomplete manifest rows, record each outcome.
2. **repair-the-apparatus** — only when the void quota trips. One cause, one
   iteration, a test that fails before and passes after. If the test passes on
   arrival, say so and call it a regression guard, not a red-then-green proof.
3. **verdict** — the manifest is full, or a ceiling was hit. Write it.

## The ledger entry

`docs/superpowers/research/goal-ledger-v4.md`. One entry per iteration, then
commit that iteration alone.

```
## <n> — <date> — <run|repair|verdict>
did: <one sentence>
cells: <recorded>/24 recorded, <void> harness-void (quota 4), <disputed> disputed
rows: <fixture>/<rounds>/<seed> -> pass|fail|harness-void: <cause>   (one line per cell run)
evidence: <commands run and the output lines the numbers came from>
next: <which action, and why>
```

Rules that survive from v3 because they earned it:

- Every number comes from a command whose output is quoted. No number from memory.
- **Record the claim you were about to make and did not.** This caught three
  would-be false headlines in v3 — a "first assertion-bearing packet" claim a
  scan of 146 packets refuted, a "the tree changed each round" inference a
  one-line diff killed, and a V6 completeness claim a compile-check disagreed
  with. It is the single highest-yield rule in this file.
- **Digest inequality is not evidence of change.** Diff the artifacts.
- Corrections are append-only: a new entry naming what it retracts.
- If a sentence in your entry contradicts a number in it, resolve it before
  committing.

## Stopping — the complete list

1. **Manifest full** → write the verdict, update ROADMAP, tell the human.
2. **The checker's self-test fails and one fix attempt does not restore it** —
   the only thing that can make results dishonest rather than merely incomplete.
3. **A budget ceiling is hit** → write the partial verdict, tell the human.
4. **ROADMAP `## Now` stops naming this experiment** — direction is the human's.

Nothing else stops the loop. Deliberately deleted triggers: "a cell fails in a
way no invariant covers" (now a `harness-void` row), "a decision touches
measurement semantics" (now the policy table and the queue), "an invariant
blocks cells after its fix landed" (now the quota rule), "two flat measure
iterations" (meaningless when the metric is manifest completion).

What is still a failure of the loop: reporting progress whose evidence would not
survive re-auditing.
