# Verdict: the 80-cell overnight ablation (2026-08-26)

**Single record for the night of 2026-08-25→26.** Supersedes and retires five
working documents (see [Provenance](#provenance--who-corrected-what)); their
retracted claims are preserved here as [history](#retracted-do-not-reuse), not
as active text.

**One-line finding:** Laguna is reliable at 39/40. **Mellum's 0/40 is a
measurement of the harness, not of Mellum** — no Mellum run in the matrix ever
reached a state where its competence was observable.

---

## 1. What was run

- **Matrix:** `{laguna, mellum} × {relative, absolute} × {think off, on} × 10
  seeds` = **80 runs**, `--spec roadmap` (the hard spec), graded by the real
  13-test acceptance suite.
- **Models:** Laguna S Q2_K (`laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`, 48 GB);
  Mellum via `--variant mellum-2.1` = `mellum-thinking-TARGET.gguf`, the 9.33 GiB
  Q4_K/Q8_0 selective build (Q4_K on expert gate/up layers 0–21, Q8_0 elsewhere)
  — **not** B8's Q8_0-only build.
- **Spec** pinned at `54253ad` (2026-08-23). The spec did not drift; the model,
  engine, and harness did, so cross-era comparisons (C13–C18) are not clean.
- Same 10 seeds in every cell, independently drawn. **Cell order was fixed**
  (all Laguna, then all Mellum), not randomized — a confound with anything that
  drifts over a 5-hour run.
- Launched idle-gated 22:18, fired 01:48, completed 07:33. All 80 exited `rc=0`.

**Primary metric:** acceptance exit code (13/13 = `exit 0`).

## 2. Results

| cell | n | reached acc | pass | exit dist | verdict dist | mean tools | zero-tool |
|---|---:|---:|---:|---|---|---:|---:|
| laguna / rel / off | 10 | 10 | **10** | {0:10} | {good:10} | 20.9 | 0 |
| laguna / rel / on | 10 | 9 | **9** | {None:1, 0:9} | {None:1, good:9} | 27.1 | 0 |
| laguna / abs / off | 10 | 10 | **10** | {0:10} | {good:10} | 24.3 | 0 |
| laguna / abs / on | 10 | 10 | **10** | {0:10} | {good:10} | 24.6 | 0 |
| mellum / rel / off | 10 | 6 | 0 | {None:4, 2:6} | {None:4, bad:6} | 0.0 | 10 |
| mellum / rel / on | 10 | 7 | 0 | {None:3, 2:7} | {None:4, bad:6} | 0.0 | 10 |
| mellum / abs / off | 10 | 5 | 0 | {None:5, 2:5} | {None:5, bad:5} | 0.0 | 10 |
| mellum / abs / on | 10 | 3 | 0 | {None:7, 2:3} | {None:7, bad:2, error:1} | 1.3 | 9 |

**Totals: Laguna 39/40. Mellum 0/40.** Every cell in this table was independently
reproduced from the captures during consolidation.

**Confidence.** Clopper-Pearson on 39/40 at 95% is **[86.8%, 99.94%]** — not
"±4%", and not "≈87–99.5%" as an earlier draft rounded it. Read Laguna as
"≈95%+", never "100%".

### The `hello`-caps counting bug

The engine's `hello` event advertises the tool capability in its `caps` array:

```
{"t":"hello","v":1,"caps":[...,"tool_request","pool"],...}
```

A naive `grep '"tool_request"'` counts that line as a tool call, inflating every
run by exactly 1 — which turns Mellum's true 0 into an apparent 1/run. **Correct
count: parse `"t":"tool_request"` events only.** Found independently by both
analysis sessions. All numbers here are post-fix. This should be fixed in the
analyzer/report path so a future naive grep cannot miscount
([open item](#5-open-work)).

## 3. Laguna — reliable, with repair doing real work

- **39/40**, all four cells. 20.9–27.1 tool calls/run, 969 total over 40. Always
  initiates.
- **Repair decomposition** (verified per capture): repair artifacts appear in
  **8/40** captures — 7 phase-repair, 2 acceptance-repair, one cell both. Of the
  8, **7 ended `exit 0`** and 1 is the single failure. So **32/40 passed with no
  repair artifacts** (implement-only ≈ 80%), 7 fired repair and passed, 1 failed.
  "Repair rescued 7" is **correlation, not causation** — the record does not show
  repair was load-bearing. Honest implement-only range: **32–39/40**.
- **The one failure:** `rel/on` seed 1, ended `stop_reason: limit` — the residual
  think-loop from C18.
- **Thinking is no longer a Laguna failure mode:** 19/20 think-on runs passed.
  C9's "0/3 with thinking" is gone.
- **Path presentation: no effect at n=10** — but Laguna is at ceiling (39/40), so
  this cannot distinguish "no lever" from "masked at ceiling." The claim is
  narrow: *presentation does not matter for an already-saturated Laguna.*
- **Zero Laguna rounds ever hit the `.validationFailed` path** — which is why
  Laguna never touches any of the four defects below.

## 4. Mellum — 0/40 is harness-blocked, not model-measured

Proximate cause of death across all 40 cells. **Read the partition as serial, not
parallel:** these are first-defect-to-fire counts. Fixing one reroutes its cells
into the next — no single fix "buys" its bucket.

| | cells | cause |
|---|---:|---|
| **D1** | **18** | `RepairLoop` **discards a round's work** on the `.validationFailed` path |
| **D2** | **20** | The acceptance suite's **module-level import chain** — pytest reports one error per round |
| **D3** | **1** | **Context overflow** — a 37,180-token repair prompt against a 32,768 context |
| **D4** | **1** | **`turnDidNotEnd`** — the sole run that made 13 tool calls, whose phase repair *succeeded* |

**No Mellum repair round in the matrix was ever shown a failing assertion.** Zero
cells reached a state where the brief's question was observable.

### D1 — `RepairLoop` throws away the round's work (18 cells)

`RepairLoop.swift:193–207`: on a `.validationFailed` receipt the loop refreshes
`lastGrade` from the real validation output and `continue`s, but leaves `head`
unchanged. Line 64 then prepares round N+1's worktree from that same base.
**Round N's file is gone.** "N rounds of repair" is really N independent
single-shot attempts; nothing accumulates.

Worst in `PhaseRepair`, whose own doc comment (`PhaseRepair.swift:6–9`)
establishes that `.validationFailed` is phase repair's *only* possible failure
mode — so **every** failing phase-repair round takes the discard path.

**Receipts** (`20260826-050316`): round 1 writes `app.py` (which imports
`models`); validation fails further along. Round 2's packet carries that
traceback forward while its own file-contents block says
`=== app.py === (file does not exist in this worktree)` — a traceback through
line 5 of a file the same packet says does not exist. Mellum correctly diagnoses
and writes `models.py`; `app.py` is gone again. `app.py` → `models.py` →
`app.py` → …

**The two files import cleanly together.** Extracted from the wire and run
against the vetted import: **exit 0**. Mellum's two rounds were individually
correct and *jointly sufficient*; the harness guaranteed they could never be
applied together.

**Proven by a red test:**
[`2026-08-26-probe-validationfailed-discards-work.patch`](2026-08-26-probe-validationfailed-discards-work.patch)
(kept; apply to reproduce). Round 2 writes only `b.txt` rather than redoing round
1's `a.txt`, isolating *survival* from *re-doing* —

```
✘ Expectation failed: (seenInRound2.value → "seed\n") == ("round1-wrote-this\n")
```

`seed\n` is the base-commit content. The existing
`RepairLoopTests.swift:285` cannot catch this: its round 2 rewrites round 1's
file, so survival is never isolated. That blind spot is why the defect shipped.

> P12.8's `953d05a` made repair *retry* on this receipt. It did not make repair
> *cumulative*. Half-fixed.

### D2 — the collection-gate chain (20 cells)

`fixtures/agenttest/acceptance/test_acceptance.py` does its work at module level:

```python
from app import app                            # line 18   gate 1
import models                                  # line 19   gate 2
from models import Complaint                   # line 20   gate 3
client = TestClient(app)                       # line 22   gate 4
SEED_COMPLAINTS = tuple(models.complaints)     # line 26   gate 5
```

pytest aborts on the first that raises — `Interrupted: 1 error during
collection`. Not one of the 13 tests runs. The grade contains exactly one error
no matter how much is wrong. Two gates against `maxCandidateRounds = 2` spends
the entire budget at the moment the suite first becomes able to speak:

| | error | cells |
|---|---|---:|
| initial grade | `ModuleNotFoundError: No module named 'models'` | **20/20** |
| round 1 grade | `AttributeError: module 'models' has no attribute 'complaints'` | **20/20** |
| round 2 grade | the suite finally collects — 12–13 failures at once | 16/20 |

**The trees were partial, not empty.** Measured across the first acceptance-grade
packet of all 21 cells that reached acceptance: **21 of 21 had `app.py` already
written**, with every other writable path reading `(file does not exist)`.
Exit 2 is the collection gate closing on a tree the model *did* write. This
matters because "empty tree" licenses the inference that repair had nothing to
work with — and D1's receipts show the opposite.

### D3 — the evidence the harness could not deliver (1 cell)

`20260826-055741` (mellum/rel/on seed 9) is the most important single cell in the
matrix. Its round-1 fix cleared **all** remaining collection gates at once. The
suite collected and produced **13 failing assertions** — the rich failure surface
no other Mellum round all night ever got. `RepairLoop` assembled the round-2
packet carrying it (`taskText` 85,421 bytes). The engine refused it:

```
"state":"error","ctx_used":37180,"ctx_size":32768,
"error":"prompt length 37180 exceeds context 32768 (one token of generation room is required)"
```

The run died with repair budget remaining and no verdict written.

**This is also GLM 5.3's finding I3.** That review flagged mellum/rel/on seed 9
as "exit 2 but no `verdict.json` — ungraded" and recorded it as a bookkeeping
anomaly. It is the same cell: the run never reached the verdict step *because*
the packet could not be prefilled. Neither source connected the two; the
consolidation did. **An ungraded cell is a symptom worth chasing, not a footnote.**

Three consequences:

1. **One round can clear multiple gates** — softening D2's strictly-serial framing
   for a model that writes more than the traceback demands.
2. **Surfacing more errors per round makes this worse** unless paired with a
   whole-packet budget. The 8192-byte cap applies to grade output only; the
   assembled packet (6 files × 16,384 `fileCap` + session context) is uncapped.
3. **There is no receipt for it** — not `contractNotFollowed`, not
   `validationFailed`, not `repairExhausted`. Any `blockedBy` classifier must
   read the wire, not just the receipts.

### D4 — `turnDidNotEnd`, and the tool-call exception (1 cell)

`20260826-065840` (abs/on seed 9) made **13 real tool calls** in its phase-2
build — 12 `write` and one `google_search`, a tool not in the grant. It is also
the only cell where phase repair *succeeded* (round-1 candidate, validation exit
0) and the pipeline advanced — before dying in phase 2 on `turnDidNotEnd` after
6,564 tokens, a failure mode nothing in the capture schema records.

**So P13's "Mellum never initiates" is *rare*, not *never*:** 39/40 zero calls,
1/40 with 13. A materially different claim.

Every Mellum turn that *ended* ended `stop_reason: eos` — so the zero-call runs
are "narrates and stops," not "ran out of tokens." Scope that carefully: D3 and
D4 died on failure modes that never produce a `stop_reason` at all.

### Two further harness defects, in the packet itself

**The directive contradicts its own evidence.** `repairPacket`
(`main.swift:255–283`) asserts unconditionally: *"Exactly one file is wrong … Do
not rewrite working files and do not add new files or routes."* In round 1 of
`060458`, **five of six** writable files did not exist. Mellum derived the
correct multi-file fix and then talked itself out of it three times, citing the
directive verbatim:

> "The corrected `models.py` should contain both the `Complaint` dataclass and
> the `complaints` list. Then, in `app.py`, we should import `complaints` from
> `models` … **However, the instructions say to emit only the corrected file that
> is wrong.** … **But the instructions say to emit only one file.** …
> **However, the instructions also say that exactly one file is wrong.** …
> Therefore, I will emit the corrected `models.py`."

That is instruction-following against an instruction that was false in context.
The directive is well-calibrated for its design target — Laguna's 2 acceptance
repair cells both passed 13/13 in round 1 fixing one real bug in one file.

**Repair is graded on requirements it is never shown.** `phaseText: directive`
(`main.swift:312`) *replaces* the phase brief; repair receives only
`sharedContext` (Mission + Tech Stack). It never sees `## Phase 1/2/3`, so it
never learns the spec requires a favicon, a Bootstrap JS bundle, an
`if __name__ == "__main__"` block, or (`specs/roadmap.md:32`) *"3-5 seed
complaints … including the exact text `Scope creep never ends.`"* Mellum wrote
`complaints: list[Complaint] = []` — correct given the packet's information — and
the verdict then failed the run for missing seed complaints.

### The one isolable Mellum error

4 of the 20 D2 cells repeated round 1's error verbatim. In `20260826-050444`
Mellum's prose is right — *"we need to add a `complaints` variable"* — then it
emits `SEED_COMPLAINTS = (...)`. The traceback's source line is
`SEED_COMPLAINTS = tuple(models.complaints)`; it defined the **left-hand side**
instead of the **right-hand side** the error names.

**Treat this as a lead, not a finding.** It is characterized from *one*
transcript; whether the other three are the same class is unverified. One
transcript cannot characterize a model.

## 5. What is and isn't established

**Established.** Laguna 39/40 with the decomposition above. The four harness
defects, each with code, receipts, and — for D1 — a red test. Mellum initiates
rarely rather than never. Mellum's repair emitted trees that were partial but
*fixable*, and jointly correct across rounds.

**Not established: anything about Mellum's repair competence.** Not measured
here — but "not measured" is not "untested." P15's repair arm already has
**Mellum 4/4 at 13/13** on the `plausible-wrong-fix` fixture, built so the
obvious correction is wrong. What no fixture yet tests is **multi-defect,
multi-file** repair; both existing fixtures are one-bug/one-file, i.e. the
directive's design target. That gap — not another matrix run — is the cheap
decisive test (fixture tier: 22–72s/round vs 2.7 min/cell).

### Retracted — do not reuse

Preserved so the correction trail survives the consolidation.

| Claim | Source | Why it's wrong |
|---|---|---|
| "Mellum agentic initiation absent; P15/P13 reinforced at n=40" | R3.5 draft | Harness-blocked; and 1/40 did initiate |
| "No further agentic Mellum work is justified" | R3.5 draft | Drawn from a harness-dominated pass rate |
| "Path presentation is not a lever" | R3.5 draft | Ceiling effect — Laguna is saturated |
| "C13's lever was the cwd-fact ambiguity" | R3.5 draft | Untested causal story; no factorial was run |
| "B8 falsified" | R3.5 draft | Different quant (Q4_K/Q8_0 vs Q8_0-only) + harness-blocked |
| "exit 2 is collection failure on an **empty tree**" | R3.5 draft | 21/21 had `app.py` written |
| "Mellum made 0 tool calls in all 38 cells" | findings draft | 78-row snapshot of a still-running chain; true count 39/40 |
| "Bucket A = 17, Bucket B = 21" | findings draft | Same snapshot; true counts 18/20/1/1 |
| "Evidence bandwidth is not the constraint" | findings draft | Refuted by D3 |
| "Two cells converge on an identical digest ⇒ deterministic non-progress" | findings draft | Digest hashes *validation output*, not emissions; 5 cells share it |
| "`blockedBy` from two `.validationFailed` rounds with distinct digests" | findings draft | Unsound both ways — see below |
| "Three harness fixes unblock all Mellum measurement" | ROADMAP draft | Partition is serial; four are needed |
| "Implement-only ≈ 77.5%, rescued ≈ 8" | R3.5 draft | Corrected to 32/40 with a 32–39 range |
| "39/40 is ±4%" | R3.5 draft | Clopper-Pearson is [86.8%, 99.94%] |

## 6. Open work

Ordered by leverage. **1–4 are all required before Mellum can be measured at
all** — the partition is serial.

1. **Make repair rounds cumulative** (finishes P12.8). Commit the round's tree
   and advance `head` on the `.validationFailed` path. `commitForRepair`
   (`WorktreeDispatcher.swift:103`) already exists. Land the probe test with it.
   One design call: whether a validation-failing tree needs a distinct ref
   namespace so it can't be mistaken downstream for a candidate.
2. **Make the directive conditional** on the count of missing writable files.
   Note this is a **seam change, not a text edit**: `RepairContext` carries only
   `failedRef`/`grade`/`round` to keep the builder worktree-independent, so the
   count has to reach the builder.
3. **Give repair the `## Phase N` brief.**
4. **Break the collection gate *and* cap the packet, together.**
   `--continue-on-collection-errors` is the cheap version; the better one is a
   precondition manifest (statically list the acceptance module's top-level
   imports and attribute accesses as met/unmet). Do not ship either without a
   whole-packet budget, or D2 deaths become D3 deaths.
5. **Record `blockedBy: harness | model`** as a derived field — from directly
   observable violations, never from digests: round N reported mutations and
   round N+1's evidence shows them missing (D1); `error during collection` (D2);
   `exceeds context` (D3); `turnDidNotEnd`/`limit` (D4).
6. **Fix the `hello`-caps miscount** in the analyzer/report path.
7. **Then re-run the Mellum arm.** ~2.7 min/cell: n=16 ≈ 45 min, the full 40-cell
   arm ≈ 1.8h.
8. **Laguna residual:** the think-loop → `limit` mode (1/20 thinking runs) is the
   target for `--think-budget` validation.
9. **A multi-file repair fixture** — the only way to test what the whack-a-mole
   brief actually asked about.

Measurement discipline for the re-run is registered as `/goal`
(`.claude/commands/goal.md`), whose metric is **valid cells, not passes**.

## 7. Provenance — who corrected what

Three independent sources produced this record, and **every substantive
correction came from re-measuring, not from re-reading**. That is the transferable
lesson.

- **R3.5 analysis session** — the matrix, the per-cell table, the `hello`-caps
  bug, the GLM dispatch, the Laguna decomposition. Its Mellum conclusions were
  retracted.
- **Harness investigation session** — D1–D2, the directive and phase-brief
  defects, the probe test. Its counts and its "0 tool calls" headline were wrong
  (snapshot of a still-running chain); D3 and D4 were missed entirely.
- **GLM 5.3 adversarial review** (read-only, `z-ai/glm-5.3`) — the ceiling
  effect, the implement-only decomposition error, the quant confound, the CI
  understatement, and I3, the ungraded cell that turned out to be D3.
- **Fable review** — caught the 80-vs-78 snapshot, the tool-call exception, D3,
  the serial-vs-parallel partition, and the unsound digest classifier.

**This is the third occurrence of one failure class:** scoring a run, then
reading the score as a fact about the model when the harness dominated it. P15
records the first ("the old 1/4 was measuring the parser, not the model"); the
Mellum 0/40 is the second and third. The `/goal` validity gate exists to make it
the last.

## 8. Where to look

- `/tmp/overnight-manifest.tsv` — 80-row index (model/path/think/seed/exit/capture)
- `captures/agenttest/20260826-*roadmap/` — 80 self-describing captures
- `20260826-050316` — D1, cleanest instance · `20260826-060458` — D2
- `20260826-055741` — D3 (= GLM's I3) · `20260826-065840` — D4, the 13-call cell
- `20260826-050444` — the isolable Mellum error
- `Sources/SwiftStarAppKit/RepairLoop.swift:193–207`, `:64` · `PhaseRepair.swift:6–9`
- `Sources/swiftstar-agenttest/main.swift:255–283`, `:312`, `:84`
  (`AGENTTEST_TEXT_CONTRACT`, never set by `Tools/overnight-chain.sh` — the one
  dial P15 proved matters for Mellum was off in all 80 cells)
- `Sources/SwiftStarKit/MachineEvidence.swift:19–36`, `:110–121`
- `fixtures/agenttest/acceptance/test_acceptance.py:18–26` ·
  `fixtures/agenttest/specs/roadmap.md:32`
- `Tests/SwiftStarIntegrationTests/RepairLoopTests.swift:285` — the blind-spot test
- `docs/superpowers/research/superseded/` — the five retired working documents
