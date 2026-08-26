# R3.5 prompt-shape ablation — seed-swept verdict (2026-08-26)

*Measured overnight 2026-08-26. 80 runs: `{laguna, mellum} × {relative, absolute} ×
{think off, on} × 10 seeds`, all `--spec roadmap` against the real acceptance suite.
Idle-gated launch via `Tools/overnight-idle-launch.sh` + `Tools/overnight-chain.sh`
(caffeinated). Spec pinned at `54253ad` (2026-08-23), which postdates the C13–C18 runs
(2026-08-24) — the *spec* did not drift; the model, engine, and harness did (see caveats).
Laguna S Q2_K via `SWIFTSTAR_MODEL`; Mellum via `--variant mellum-2.1` =
`~/models/mellum-thinking-TARGET.gguf`, the 9.33 GiB Q4_K/Q8_0 selective build (P12.2/P13),
**not** B8's Q8_0-only. Same 10 seeds used in every cell, independently drawn per run.
Reviewed by GLM 5.3 — see `2026-08-26-r35-prompt-shape-ablation-glm53-review.md`. **The
Mellum conclusions below are superseded** by
[`2026-08-26-mellum-repair-harness-findings.md`](2026-08-26-mellum-repair-harness-findings.md)
— the 0/40 is harness-blocked, not model-measured. The Laguna side stands.*

## The question

D6 (overnight consolidation) named the prompt-shape ablation "the single experiment
that could most change the roadmap": it bore on whether "Laguna 0/3 with thinking" (C9)
was a prompt artifact, whether Mellum's initiation failure was prompt-shaped (B8), and
whether `--think-budget` solves a real problem. R3.5: relative-vs-absolute presentation ×
thinking on/off, both models, real acceptance suite. This is that experiment, seed-swept
to n=10 per cell.

## Measured

Primary metric: acceptance exit code (13/13 = `exit 0`). Tool calls counted as
`"t":"tool_request"` events, excluding the engine `hello` event's `caps` advertisement
(the same substring appears there — corrected during write-up; the rule was re-applied to
all 80 runs and the per-seed breakdowns below were produced under it).

| cell | n | reached acc | pass (exit 0) | acc exit dist | verdict dist | mean tools | zero-tool runs |
|---|---|---|---|---|---|---|---|
| laguna / relative / off | 10 | 10 | **10** | {0:10} | {good:10} | 20.9 | 0 |
| laguna / relative / on | 10 | 9 | **9** | {None:1, 0:9} | {None:1, good:9} | 27.1 | 0 |
| laguna / absolute / off | 10 | 10 | **10** | {0:10} | {good:10} | 24.3 | 0 |
| laguna / absolute / on | 10 | 10 | **10** | {0:10} | {good:10} | 24.6 | 0 |
| mellum / relative / off | 10 | 6 | 0 | {None:4, 2:6} | {None:4, bad:6} | 0.0 | 10 |
| mellum / relative / on | 10 | 7 | 0 | {None:3, 2:7} | {None:4, bad:6} | 0.0 | 10 |
| mellum / absolute / off | 10 | 5 | 0 | {None:5, 2:5} | {None:5, bad:5} | 0.0 | 10 |
| mellum / absolute / on | 10 | 3 | 0 | {None:7, 2:3} | {None:7, bad:2, error:1} | 1.3 | 9 |

**Totals: Laguna 39/40 pass. Mellum 0/40 pass.**

For Mellum, "reached acc" means the run survived to the acceptance step. The harness writes
its own `test_acceptance.py` into the worktree and runs pytest regardless of model output;
the collection fails (`ModuleNotFoundError: No module named 'models'`) and pytest exits 2.

**Corrected — the tree was not empty.** An earlier version of this paragraph called the 21
"exit 2" runs "the harness failing to collect on an empty tree." Measured against the
first acceptance-grade packet of each of those 21 cells, **21 of 21 had `app.py` already
written** — by phase repair, under the text contract. Every other writable path reads
`(file does not exist in this worktree)`, so exactly one file was present in every case.
So exit 2 is the collection gate closing on a *partial* tree the model did write, not on an
empty one. The distinction is load-bearing: "empty tree" invites the inference that repair
had nothing to work with, and
[`2026-08-26-mellum-repair-harness-findings.md`](2026-08-26-mellum-repair-harness-findings.md)
shows the opposite — in `20260826-050316` the two files Mellum emitted across two rounds
import cleanly *together*; the harness discarded the first before applying the second.

Every one of the 40 Mellum runs ended `stop_reason: eos` (natural turn end, not a token
wall) — so the 0-tool-call runs are "narrates and stops," not "ran out of tokens." Note the
scope: `stop_reason` describes turns that ended. Two cells died on failure modes that never
produce one — a `state: error` context overflow (`055741`) and a `turnDidNotEnd`
(`065840`) — so this does not mean all 40 runs ended cleanly.

## Findings

### 1. Path presentation: no effect at n=10, but untestable at the ceiling

Laguna passes under both presentations (relative 19/20, absolute 20/20); Mellum initiates
under neither (0 tool calls in 9/10 of both absolute cells and 10/10 of both relative cells).
**But Laguna is at ceiling** (39/40), so a presentation effect of the size C13 reported —
at a low base rate — would be masked. The falsifiable claim is narrow: *presentation does
not matter for an already-saturated Laguna, and it does not restore Mellum's initiation
under this quant/harness.* It does **not** establish "path presentation is not a lever" in
general.

### 2. C13's "path lever" did not replicate — explanation is a hypothesis, not a finding

C13 (n=3) reported absolute presentation taking Laguna phase-1 completion 0/3 → 2/3. At
n=10 that effect is gone. The plausible story — that C13's lever was really the cwd-fact
ambiguity, pinned in C14 — is **not directly tested** (no cwd-fact × presentation factorial
was run), and C14's fix is confounded with every other harness change between C13 and now.
The honest claim is "did not replicate under current conditions," not "was the cwd fact."

### 3. Mellum: 0/40 is harness-blocked, not model-measured

*Superseded by
[`2026-08-26-mellum-repair-harness-findings.md`](2026-08-26-mellum-repair-harness-findings.md),
which read the same 40 cells end-to-end against the harness source. This record's earlier
reading — "agentic initiation absent, P15 reinforced" — was wrong; retained here only as a
correction trail.*

The 40 Mellum cells died of harness defects, not of a cleanly observable model failure:
**18** stopped on the `RepairLoop` discard defect (a round's work is undone before the next
round starts on the `.validationFailed` path, so phase repair is never cumulative); **20** on
the acceptance suite's module-level import chain (pytest reports exactly one error per round,
and two gates × two rounds exhausts the budget at the moment the suite first becomes able to
speak); **1** on context overflow (a 37,180-token repair prompt against a 32,768 context);
**1** is the sole run where Mellum made 13 real tool calls, phase repair *succeeded*, and the
run then died on `turnDidNotEnd`. Zero cells reached a state where the question was
observable.

The tool-call count stands and is shared with that record: **39/40 zero calls, one run made
13** (`write`×12 + a nonexistent `google_search`) — so P13's "never initiates" is **rare, not
never**. Every Mellum run ended `stop_reason: eos`. Nothing about Mellum's repair competence
can be concluded from this matrix; the harness fixes in the findings doc must land first.

### 4. Laguna: reliable, with repair doing real work — decomposed honestly

Repair artifacts (`repair-phase*`/`repair-packet*` dirs) appear in **8/40** Laguna captures.
Of those 8, **7 ended `exit 0`** and **1 is the failure** (`relative/on` seed 1, the
think-loop). So:

- 32/40 passed with no repair artifacts (implement-only ≈ **80%**),
- 7/40 passed with repair artifacts,
- 1/40 failed (repair fired and the run still think-looped).

"Repair rescued 7" is correlation, not causation — repair fired and the run passed, but the
record does not prove repair was the cause. The honest range for implement-only is 32–39/40.

### 5. Thinking is no longer a Laguna failure mode

19/20 thinking runs passed (9/10 relative, 10/10 absolute); the one failure ended
`stop_reason: limit` (the residual think-loop). Thinking did not change Mellum (9/10 zero-call
in the think-on cell that also contained the single initiating run).

## Caveats

1. **"Pass" is implement + repair.** The implement-only rate is ≈80% (32/40) — possibly up
   to 39/40 if repair merely fired without being load-bearing. Compare the pre-repair era
   (C18: 3/9) only with the caveat that the engine and harness also changed since C18, so
   the improvement is not cleanly attributable to repair.
2. **n=10/cell, and the CI is wider than it looks.** Clopper-Pearson for 39/40 is roughly
   **87–99.5%** at 95% confidence — "≥~87%," not "≈95%+."
3. **Acceptance exit codes are the metric** (D3 rule); DeepSeek `good` verdicts agree except
   for one data-quality gap: `mellum/relative/on` seed 9 has `exit 2` but **no verdict.json**
   (grader produced no verdict), leaving `{None:4, bad:6}` verdicts against `{None:3, 2:7}`
   exits — one exit-2 run ungraded. Unexplained.
4. **Repair-firing is inferred from capture artifacts**, not a first-class counter.
5. **Cell order was fixed** (Laguna first, then Mellum; not randomized), so machine state
   (thermal, memory) is a possible between-cell confound.
6. **Mellum quant differs from B8's** (see header) — the cross-model comparison is not
   quant-matched.

## What this changes

- **R3.5 is closed with a null** — but a *narrow* null: presentation does not matter for an
  already-saturated Laguna, and it does not restore Mellum under this quant/harness. It
  retired a direction rather than opening one.
- **Mellum remains unmeasured, not non-agentic.** The 0/40 is harness-blocked (see the
  findings doc), so P15's verdict is neither reinforced nor weakened by this matrix. Re-run
  the Mellum arm after the four harness fixes land.
- **Laguna is reliable enough to proceed** (≥~87% at 95% CI, with repair in the loop) to the
  P12.8-vs-P14 decision. The P12.8 gap is narrower than the backlog wording suggests: repair
  already fires at the import gate.
- **Residual Laguna mode**: think-loop → `limit` (1/20 thinking runs), the one unfixed mode
  from C18 — the target for `--think-budget` validation.

## Artifacts

- Per-run index: `/tmp/overnight-manifest.tsv` (model/path/think/seed/exit/capture).
- Captures: `captures/agenttest/20260826-*roadmap/` (80 self-describing dirs).
- Logs: `/tmp/overnight-idle-launch.log`, `/tmp/overnight-chain.log`.
- Runners (untracked): `Tools/overnight-idle-launch.sh`, `Tools/overnight-chain.sh`;
  aggregation: `/tmp/analyze-overnight.py`.
