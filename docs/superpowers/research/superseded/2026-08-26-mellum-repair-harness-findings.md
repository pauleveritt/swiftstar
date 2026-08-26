# Findings: the whack-a-mole was the harness, not Mellum

**Date:** 2026-08-26. **Supersedes:**
[`2026-08-26-mellum-whack-a-mole-repair-brief.md`](2026-08-26-mellum-whack-a-mole-repair-brief.md),
whose (a)/(b)/(c) question **cannot be answered from this data** — see
[Verdict](#verdict). **Evidence:** the full 80-cell overnight matrix
(`/tmp/overnight-manifest.tsv`), read end to end, plus `RepairLoop.swift`,
`PhaseRepair.swift`, `repairPacket` in `main.swift`, and a failing probe test.
**Revised 2026-08-26 after Fable's review** — the first draft was written against a
78-row snapshot taken while the chain was still running, and its counts and its
"0 tool calls" headline were both wrong. Corrections are marked inline.

---

## Headline

Across **40 Mellum cells, 0 reached a state where the brief's question was
cleanly observable.** Proximate cause of death, by cell:

| | cells | stopped by |
|---|---:|---|
| A | **18** (45%) | `RepairLoop` **discards a round's work** on the `.validationFailed` path, so phase repair is never cumulative. Run died before the acceptance suite ever ran. |
| B | **20** (50%) | The acceptance suite's **module-level import chain** makes pytest report exactly one error per round. Two gates, two rounds — budget gone at the moment the suite first becomes able to speak. |
| C | **1** | **Context overflow.** The one cell where the harness had real failing assertions to show, it could not deliver them: `prompt length 37180 exceeds context 32768`. See [Defect 3](#defect-3--the-evidence-the-harness-could-not-deliver-1-cell). |
| D | **1** | Mellum made 13 real tool calls, phase repair *succeeded*, and the run then died in phase 2 on `turnDidNotEnd`. |
| Passed | **0** | — |

**Read the partition as serial, not parallel.** These are first-defect-to-fire
counts, not independent kill counts. Fixing A alone reroutes those 18 cells into
B's collection gates — templates and seed complaints still do not exist. No
single fix "buys" its bucket.

Within bucket B, **4 cells died proximately of a genuine model error**, not the
gate chain — see [the one genuine Mellum error](#the-one-genuine-mellum-error).
The headline claim is that no round was ever shown a failing assertion, which
holds; it is *not* that Mellum made no mistakes.

Contrast: **Laguna, 39/40 `good`**, and **zero** Laguna rounds ever hit the
`.validationFailed` path. Laguna's build phase clears the gates itself, so it
never touches either defect. The matrix did not compare two models on repair;
it compared one model that avoids two bugs against one that hits both every
time.

**Reconciled with the R3.5 verdict record** — a parallel session measured this
same 80-cell matrix as a prompt-shape ablation
([`2026-08-26-r35-prompt-shape-ablation-verdict.md`](2026-08-26-r35-prompt-shape-ablation-verdict.md),
adversarially reviewed by GLM 5.3 in
[`…-glm53-review.md`](2026-08-26-r35-prompt-shape-ablation-glm53-review.md)).
The two records now agree, and each corrected the other:

- That record independently caught the `hello`-caps tool-counting bug and the
  80-cell count that this doc's first draft got wrong.
- This doc supersedes its Mellum conclusions — its "agentic initiation absent,
  P13 reinforced, no further Mellum work justified" reading was drawn from a
  harness-dominated pass rate. Its Mellum section now carries this taxonomy.
- This doc corrected its remaining factual claim that exit 2 was "collection
  failure on an empty tree." Measured across the first acceptance-grade packet
  of all 21 cells that reached acceptance: **21 of 21 had `app.py` already
  written**, exactly one file present in each. The trees were partial, not
  empty — which is why "repair cannot rescue a model that never emits a fixable
  tree" is the wrong inference. It emitted one; the harness threw it away.
- Its **Laguna decomposition is new and stands**, and belongs here: repair
  artifacts appear in **8/40** Laguna captures (verified: 7 phase-repair, 2
  acceptance-repair, one cell both). Of those 8, 7 ended `exit 0` and 1 is the
  single Laguna failure. So implement-only is **32/40 (≈80%)**, and "repair
  rescued 7" is correlation, not causation — the honest range for implement-only
  is 32–39/40. Laguna's 39/40 is *implement + repair*, not implement alone.

This is the same class of error the P15 memory records — *"the old 1/4 was
measuring the parser, not the model."* Second occurrence. See
[recommendation 7](#7-make-harness-blocked-vs-model-wrong-a-recorded-field).

---

## Corrections to the brief's premises

**1. "The build phase wrote nothing" — true in 39 of 40 cells, not all of them.**
*(Corrected. The first draft claimed a clean zero at n=38; that was an artifact of
the 78-row snapshot.)* Mellum made 0 real tool calls in **39 of 40** cells. The
`grep`-able `tool_request` hit in each `wire.ndjson` is a capability
advertisement in the `hello` line, not a call
(`{"t":"hello","caps":[...,"tool_request",...]}`). But
`captures/agenttest/20260826-065840-roadmap` (absolute/on, seed 9) is the
exception: **13 real tool calls** in its phase-2 build — 12 `write` and one
`google_search`, a tool that does not exist in the grant. Laguna: 969 real tool
calls over 40 cells.

So P13's standing finding is **"rare," not "never,"** which is a materially
different claim. That cell is also the only one where phase repair *succeeded*
(round-1 candidate, validation exit 0) and the pipeline advanced — before dying
in phase 2 on `turnDidNotEnd` after 6,564 tokens, a failure mode nothing in the
capture schema records.

**2. "Its 2 rounds" — it was a 3-round chain, and the brief read rounds 2 and 3.**
In `20260826-060458-roadmap` the sequence was one *phase-scoped* repair round
(wrote `app.py`, produced a candidate, `repair-phase1/repair-round-1.json`)
followed by two acceptance rounds. The `app.py` visible in
`repair-packet-1.json` is that phase-repair round's output, not the build's.

**3. "Repair only ever shows one traceback at a time" — the framing hypothesis
was right, but not for the reason given.** `MachineEvidence` passes the *whole*
grade output (8192-byte tail cap) plus the full current contents of every
writable file. Nothing is being truncated away. The suite genuinely only
*produces* one error, because it fails at collection. See
[Defect 2](#defect-2--the-collection-gate-chain-20-cells).

**4. The final grade was 12 failed / 1 passed**, not 10/3, and the dominant
failure was `TemplateNotFound: 'complaints.html'` — templates never written.

**5. The matrix is 80 cells, not 78.** The chain was still running when the first
draft snapshotted `/tmp/overnight-manifest.tsv`; two Mellum cells landed at
07:32 and 07:34. Both matter: one is the 13-tool-call cell above, the other a
clean bucket-A death that moves that count from 17 to 18.

---

## Defect 1 — `RepairLoop` throws away the round's work (18 cells)

### The defect

`RepairLoop.swift:193–207`. On `.receipt(.validationFailed)` the loop refreshes
`lastGrade` from the real validation output and `continue`s — but leaves `head`
unchanged, with the comment *"head stays unchanged since no candidate was
produced to advance to."* Line 64 then prepares round N+1's worktree from that
same unchanged `baseRef`. **Round N's file is gone.**

So "2 rounds of repair" is not two rounds. It is two *independent single-shot
attempts*, each starting from the same empty tree. Nothing accumulates.

### Why this is catastrophic specifically in `PhaseRepair`

`PhaseRepair.swift:6–9` states the invariant in its own doc comment: *"`finalize`
returns `.candidate` only after validation already passed, so the import check is
the real gate and `grade` cannot meaningfully fail."* Which means: **in phase
repair, `.validationFailed` is the only possible failure mode.** Every failing
phase-repair round takes the discard path. Phase repair can therefore only ever
succeed if one single round fixes everything at once.

### The receipts

`captures/agenttest/20260826-050316-roadmap` — Mellum did exactly the right
thing, twice, and the harness undid it:

- **Round 1** evidence: `import app` → `ModuleNotFoundError: No module named 'app'`.
  Mellum writes `app.py`, which contains `from models import Complaint`.
  Validation now fails *further along*: `File ".../app.py", line 5, in <module>
  / from models import Complaint / ModuleNotFoundError: No module named 'models'`.
  → `.validationFailed`, worktree discarded.
- **Round 2** evidence carries that traceback forward — but the file-contents
  block in the *same packet* says:

  ```
  === app.py ===
  (file does not exist in this worktree)
  ```

  The packet shows the model a traceback walking through line 5 of a file it
  simultaneously tells the model does not exist. Mellum correctly diagnoses the
  new error and writes `models.py`. But `app.py` is gone again, so `import app`
  fails with `No module named 'app'` — back to round 1's error. Budget gone.

`app.py` → `models.py` → `app.py` → … Mellum's two rounds were individually
correct and **jointly sufficient**. The harness guaranteed they could never be
applied together.

**Five** cells share the round-2 digest `sha256:24bc3bc7…`. *(Corrected: the
first draft said two, and implied identical model output.)* The digest hashes the
**validation output**, not the model's emission — `24bc3bc7` is
`sha256` of `ModuleNotFoundError: No module named 'app'`, verified directly. So it
proves round 2 landed back on round 1's error, which is the ping-pong; it does
**not** prove Mellum emitted the same file twice.

### Proof

A probe test at
[`2026-08-26-probe-validationfailed-discards-work.patch`](2026-08-26-probe-validationfailed-discards-work.patch)
(reverted from the tree; apply to reproduce). It differs from the existing
`validationFailedReceiptRetriesWithFreshEvidence` in one way that matters: round
2 writes **only** `b.txt` rather than redoing round 1's `a.txt`, so the assertion
isolates *survival* from *re-doing*. The existing test passes only because its
round 2 happens to rewrite round 1's file — the blind spot that let this ship.

```
✘ Expectation failed: (seenInRound2.value → "seed\n") == ("round1-wrote-this\n")
  ↳ round 2 saw a.txt = seed — round 1's write did not survive
```

`seed\n` is the base-commit content. Confirmed against code, wire, receipts, and
now a red test — four independent lines.

> Note for ROADMAP: the "Now" section says P12.8's retry-on-receipt fix landed
> (`953d05a`) and that *"phase-level repair has not fired again since the fix
> landed."* It fired **38 times** that night, and 17 of those runs died on the
> half of the defect the fix did not address. The fix made repair retry with
> fresh evidence; it did not make repair cumulative.

---

## Defect 2 — the collection-gate chain (20 cells)

`fixtures/agenttest/acceptance/test_acceptance.py` does its work at **module
level**:

```python
from app import app          # line 18   gate 1
import models                # line 19   gate 2
from models import Complaint # line 20   gate 3
client = TestClient(app)     # line 22   gate 4
SEED_COMPLAINTS = tuple(models.complaints)   # line 26   gate 5
```

pytest aborts collection on the *first* one that raises —
`Interrupted: 1 error during collection`. Not one of the 13 tests runs. The
grade output contains exactly one error, no matter how much is wrong.

The consequence is visible as an exact constant across all 20 cells:

| | error | cells |
|---|---|---:|
| initial grade | `ModuleNotFoundError: No module named 'models'` | **20/20** |
| round 1 grade | `AttributeError: module 'models' has no attribute 'complaints'` | **20/20** |
| round 2 grade | the suite finally collects — 12–13 failures at once | 16/20 |

Two gates. Two rounds. `RepairLoop`'s default `maxCandidateRounds = 2` is spent
*exactly* at the moment the suite first becomes capable of reporting a test
failure. **No Mellum repair round in the entire matrix ever saw a single failing
assertion.** It is not that Mellum patched symptom-by-symptom instead of
holistically — it is that the harness only ever showed it one symptom, because
that is all pytest emitted.

~~Note the headroom: evidence bandwidth is not the constraint.~~ **Refuted by
Defect 3 below** — bandwidth *is* a constraint, precisely at the point where the
evidence gets rich. The 8192-byte cap applies to grade output only; the assembled
packet as a whole (6 files × a 16,384-byte `fileCap`, plus session context) is
uncapped, and it overflows. *(The first draft also said every evidence block
carries three identical FastAPI `DeprecationWarning`s; dispatched packets carry
0–2.)*

---

## Defect 3 — the evidence the harness could not deliver (1 cell)

`captures/agenttest/20260826-055741-roadmap` is the most important single cell in
the matrix, and the first draft missed it.

Its round-1 fix cleared **all** remaining collection gates at once. The suite
collected and produced **13 failing assertions** — a real, rich, complete failure
surface, the one thing no other Mellum round all night ever got. `RepairLoop`
assembled the round-2 packet carrying it: `taskText` 85,421 bytes. And the engine
refused to prefill it. From the wire, verbatim:

```
"state":"error","ctx_used":37180,"ctx_size":32768,
"error":"prompt length 37180 exceeds context 32768 (one token of generation room is required)"
```

The run died with repair budget remaining and no verdict written.

Three consequences:

1. **One round can clear multiple gates.** That softens the deterministic "two
   gates, two rounds" framing of Defect 2 — the chain is not strictly serial for
   a model that writes more than the traceback demands.
2. **Recommendation 4 makes this worse unless paired with a total-packet
   budget.** Surfacing more errors per round pushes more rounds over the context
   ceiling. See the amended [recommendation 4](#4-break-the-collection-gate--the-highest-leverage-new-machinery).
3. **There is no receipt for this.** It is not `contractNotFollowed`, not
   `validationFailed`, not `repairExhausted` — it is an engine-level error with
   no corresponding capture record, which is why a `blockedBy` classifier must
   read the wire and not just the receipts.

---

## The directive tells Mellum not to fix it

`repairPacket` (`main.swift:255–283`) sends this, unconditionally, in both the
phase-scoped and acceptance variants:

> **"Exactly one file is wrong."** … "emit the heading line for **that file**" …
> **"Do not rewrite working files and do not add new files or routes."**

In round 1 of `060458`, **five of six** writable files did not exist. The
statement is simply false, and the prohibition forbids the only correct action.

Mellum noticed. Verbatim, from `wire.ndjson` worker 2, round 2 — it derives the
right holistic fix and then talks itself out of it three times, each time citing
the directive:

> "The corrected `models.py` should contain both the `Complaint` dataclass and
> the `complaints` list. Then, in `app.py`, we should import `complaints` from
> `models` instead of defining it locally. **However, the instructions say to
> emit only the corrected file that is wrong.** … **But the instructions say to
> emit only one file.** … **However, the instructions also say that exactly one
> file is wrong.** … Therefore, I will emit the corrected `models.py`."

That is not a reasoning-depth limit. That is instruction-following, against an
instruction that was false in context.

The directive is well-calibrated for its design target — Laguna's 2 acceptance
repair cells both passed 13/13 in round 1, fixing one real bug in one file. It
is catastrophically mis-calibrated for "reconstruct six files from nothing."

---

## Repair is graded on requirements it is never shown

`repairPacket` passes `phaseText: directive` — the directive **replaces** the
phase brief. Repair receives only `sharedContext`: the roadmap's Mission and Tech
Stack boilerplate (1,506 bytes, byte-for-byte the same block the build packet
gets). It never sees `## Phase 1 — Home Page`, `## Phase 2`, or `## Phase 3`.

So repair never learns that the spec requires a favicon link, a Bootstrap 5 JS
bundle, a hero section with the exact tagline, an `if __name__ == "__main__"`
block, a `TestClient` smoke test — or, per `specs/roadmap.md:32`, *"3-5 seed
complaints … including the exact text `Scope creep never ends.`"*

Mellum wrote `complaints: list[Complaint] = []`. The brief reads that as an
incomplete fix. It is a *correct* fix given the information in the packet:
nothing in it says seeds are required. `verdict.json` then fails the run for
*"Missing seed complaints in models.py"* and *"Missing 'Scope creep never ends.'
in seed complaints."* Substantially all 12 verdict reasons in that capture are
Phase-brief requirements repair was never told about.

---

## The one genuine Mellum error found

4 of the 20 bucket-B cells repeated round 1's error verbatim in round 2. In
`20260826-050444-roadmap`, Mellum's prose is right — *"we need to add a
`complaints` variable in `models.py`"* — and then it emits:

```python
SEED_COMPLAINTS = (
    Complaint(agent_name="AgentA", ...),
)
```

Wrong identifier. The traceback source line is
`SEED_COMPLAINTS = tuple(models.complaints)`; Mellum defined the **left-hand
side** (the test module's own local) instead of the **right-hand side** (the
attribute the error names). A real, narrow, nameable failure — reading a
traceback's source line — not an inability to fix holistically. It is also the
*only* model-side failure this investigation could isolate, in 40 cells — and it
is characterized from **one** transcript (`050444`); whether the other three are
the same class is unverified. One transcript is thin evidence for a
characterization, and this section should be read as a lead, not a finding.

---

## Verdict

The brief's (a)/(b)/(c) is **unanswerable from this run**, and re-running the
matrix unchanged would not answer it either.

- **(a) Budget too small?** Not the binding constraint. With Defect 1,
  extra rounds add nothing — each round restarts from the same empty tree.
- **(b) Framing?** **Yes, and it is the whole story** — but three-layered, and
  none of the layers is evidence truncation: the *grader* emits one error
  (collection gate), the *directive* asserts "exactly one file is wrong" and
  forbids adding files, and the *packet* withholds the phase brief that defines
  correctness.
- **(c) Reasoning-depth limit?** **Not measured here** — no Mellum round in 40
  cells was ever *shown* a failing assertion (one packet carrying 13 of them was
  assembled and then refused by the engine, Defect 3). But "not measured" is not
  "untested": P15's repair arm already has **Mellum 4/4 at 13/13** on the
  `plausible-wrong-fix` fixture, which is built so that the obvious correction is
  wrong. What no fixture yet tests is *multi-defect, multi-file* repair — both
  existing fixtures are one-bug/one-file, i.e. the directive's design target.
  That gap, not another matrix run, is the cheap decisive test.

---

## Recommendations

Ordered by leverage per unit of work. 1–3 are small and unblock measurement.

### 1. Make repair rounds cumulative (finishes P12.8)
On `.validationFailed`, commit the round's tree to a throwaway ref and advance
`head` to it. The invariant worth keeping is *"a validation-failing tree must not
be chained into the next **phase**"* — it says nothing about the next **round**,
and cumulative rounds are the only thing that makes the word "rounds" mean
anything. Land the probe test alongside; the existing test cannot catch this.

### 2. Stop asserting things the packet's own evidence contradicts
`RepairLoop` already computes which writable paths are `(file does not exist)` —
but *after* `packetBuilder` runs, and `RepairContext` deliberately carries only
`failedRef`/`grade`/`round` to keep the builder worktree-independent. So this is
a **seam change, not a text edit**: the missing-file count has to reach the
builder. Make the directive conditional on that count:
- 1 missing/failing → today's text, unchanged (it works — see Laguna).
- ≥2 → *"N of these files are missing. Emit all N,"* and drop "do not add new
  files." Fixing #1 also removes the "exists in the traceback / does not exist in
  the evidence" contradiction, which is a downstream symptom of the same discard.

### 3. Give repair the phase brief
Append the `## Phase N` section(s) covering the writable files in scope. Cheap,
and it is currently the difference between "repair failed" and "repair was never
told what correct means."

### 4. Break the collection gate — **and cap the packet at the same time**
Do not ship this without a total-packet budget. Defect 3 shows a single rich
failure surface already overflows the 32,768-token context at 85 KB of
`taskText`; surfacing *more* errors per round without a whole-packet cap converts
bucket-B deaths into bucket-C deaths. Budget the assembled packet, and spend it
on a ranked failure list rather than on repeated tracebacks and warnings.

Cheap version: run the grader with `--continue-on-collection-errors` so more than
one error surfaces per round. Better version: a **precondition manifest** built
before repair — statically walk the acceptance module's top-level imports and
attribute accesses (`app`, `models`, `models.complaints`, `models.Complaint`) and
report each as met/unmet, alongside per-writable-file existence and
importability. That converts a serial gate chain into a single parallel worklist,
which is what the model needs to plan one complete fix instead of N sequential
ones. The 8192-byte cap has room: replace three duplicate `DeprecationWarning`s
with a 10-line manifest.

### 5. Flip the one dial the matrix never tried
`AGENTTEST_TEXT_CONTRACT=1` exists (`main.swift:84`) and
`Tools/overnight-chain.sh` **never sets it** — the matrix varied seed, path
style, and thinking across 78 cells while holding the build phase plain-agentic
in every one. Mellum makes 0 tool calls there and writes real code under the text
contract, which P15 already established. Today, `repair` is doing `implement`'s
job with `repair`'s 2-round budget and `repair`'s "exactly one file is wrong"
directive — the roles are miscast. Routing Mellum's *build* through the text
contract is a smaller change than teaching repair to build, and it lets repair go
back to what it is designed and measured for. **This is the variable worth
flipping next.**

### 6. Only then re-ask the brief's question
With 1–5 in place, re-run the matrix. Only at that point is (c) observable.
Prediction on the current evidence: Mellum's residual failures will be narrow and
nameable (the `SEED_COMPLAINTS`/`complaints` LHS-RHS class), not "cannot fix
holistically."

### 7. Make "harness-blocked" vs "model-wrong" a recorded field
All 40 cells recorded `bad` / `error` / no verdict, which reads as *the model
failed*. Nothing in the capture distinguishes "the model produced a wrong fix"
from "the harness discarded the model's correct fix." A derived per-run
classification would have reduced this entire investigation to a `grep`.

**Do not derive it from digests.** *(Corrected — the first draft proposed exactly
that.)* The digest hashes validation output, not the model's emission, so
distinct digests do not establish the model changed its answer and identical ones
do not establish it didn't; a model emitting two different, individually broken
files would be misclassified as harness-blocked. Derive it from directly
observable violations instead, each a grep with no inference:

- round N reported mutations, and round N+1's evidence shows those files missing
  (definitionally the discard — Defect 1);
- grade output contains `error during collection` (Defect 2);
- wire contains `exceeds context` (Defect 3);
- turn ends `turnDidNotEnd` or `limit` (the 065840 mode, currently unrecorded).
Given that the P15 memory already records one instance of measuring the harness
and reading it as the model, this is a recurring, expensive confusion and worth
closing permanently rather than case by case.

---

## Where to look (verified paths)

- `Sources/SwiftStarAppKit/RepairLoop.swift:193–207` (the discard), `:64` (the
  re-prepare from unchanged `head`)
- `Sources/SwiftStarAppKit/PhaseRepair.swift:6–9` (why the discard path is the
  *only* failure mode there)
- `Sources/swiftstar-agenttest/main.swift:255–283` (the directive), `:84`
  (`AGENTTEST_TEXT_CONTRACT`), `:312` (`phaseText: directive` replacing the
  phase brief)
- `Sources/SwiftStarKit/MachineEvidence.swift:19–36` (tail cap — not the
  bottleneck), `:110–121` (render)
- `fixtures/agenttest/acceptance/test_acceptance.py:18–26` (the five gates);
  `fixtures/agenttest/specs/roadmap.md:32` (the withheld seed requirement)
- `captures/agenttest/20260826-050316-roadmap/` — Defect 1, cleanest instance
- `captures/agenttest/20260826-060458-roadmap/` — Defect 2, the brief's capture
- `captures/agenttest/20260826-050444-roadmap/` — the genuine Mellum error
- `captures/agenttest/20260826-055741-roadmap/` — Defect 3, the context overflow
- `captures/agenttest/20260826-065840-roadmap/` — the 13-tool-call cell
- `Tests/SwiftStarIntegrationTests/RepairLoopTests.swift:285` — the existing test
  whose round 2 redoes round 1's work, which is why the defect shipped
