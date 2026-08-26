# P17 verdict — budget, framing, or depth? Neither, mostly.

**2026-08-26.** Pre-registered fixture-tier experiment, 24 cells, manifest
complete, 1 harness-void. Answers the question the
[whack-a-mole brief](2026-08-26-mellum-whack-a-mole-repair-brief.md) asked and
the [80-cell verdict](2026-08-26-overnight-80-cell-verdict.md) could not.

## The answer in one paragraph

Mellum's multi-file repair failure was **predominantly a harness defect, not a
model limit**: the repair directive asserted *"Exactly one file is wrong"* on
every cell, including cells where three files were wrong. With that claim
removed, **repair depth stops predicting failure** — Mellum fixes three coupled
files across three file types in a single turn. The **round budget has no
measurable effect on editing tasks**. The one place a real limit survives is not
depth, budget, or evidence-shape: it is being asked to **author a file from
scratch whose required contents are only implied by the test suite**, where
Mellum stalls at the same unmet precondition for five consecutive rounds.

## Numbers

Pass rate by files-that-must-change, both budgets pooled. **n = 3 per cell; the
intervals are wide and no claim here should be read as precise.**

| fixture | files to fix | task | rounds=2 | rounds=5 | pooled |
|---|---|---|---|---|---|
| `plausible-wrong-fix` | 1 | edit | 3/3 | 3/3 | **6/6** |
| `depth-2` | 2 | edit | 2/2 valid | 2/3 | **4/5** |
| `depth-3` | 3 | edit | 3/3 | 2/3 | **5/6** |
| `framing-2` | 2 | **author + edit** | 0/3 | 1/3 | **1/6** |

Editing tasks pooled across depth 1→3: **15/17**. The authoring task: **1/6**.

### Budget

| | rounds=2 | rounds=5 |
|---|---|---|
| editing fixtures (depth 1–3) | 8/8 valid | 7/9 |
| `framing-2` | 0/3 | 1/3 |

**More rounds did not help editing** — if anything slightly worse, well inside
noise at n=3. Extra rounds helped only where the model had a precondition gate
to clear first, and the single `framing-2` pass shows why: round 1 stuck on the
precondition, round 2 through it, **round 3 to 13/13**. A 2-round budget cannot
express that arc. This is the controlled budget comparison v2 could not make —
the starting tree is pinned by a commit, so the confound that made v2's
comparison worthless is gone by construction.

### Depth

Flat. 6/6 → 4/5 → 5/6 from one file to three. The two failures are single cells
at rounds=5, not a trend. `depth-3` requires changing a FastAPI route argument,
a dataclass `default_factory`, and an HTML attribute — three files, three
languages — and Mellum did it in **one turn**:

```
turn 1: headings=['app.py', 'models.py', 'templates/base.html']  -> 13/13
```

## What actually caused the original whack-a-mole

The directive. `RepairContext.missingWritableFiles` counts files that are
**absent**; a file that is present and broken is invisible to it, so the
single-file branch fired for 0-missing/3-broken. Same fixtures, same model, same
seeds — only the directive changed:

| | false directive | corrected |
|---|---|---|
| `depth-2` | **0/3** | 2/3 |
| `depth-3` | 2/3 | **3/3** |

Under the false directive the wire shows the model obeying it exactly — emitting
`app.py` twice across two rounds while both residual failures were in
`base.html`, a file it was never asked to touch. The 80-cell verdict recorded
Mellum "citing this exact text back three times to justify not making" a
multi-file fix. It was not rationalising; it was following instructions.

**This is the fourth time in this project a number about Mellum turned out to be
a number about the harness.** It was caught here only because `depth-3` — a
strict superset of `depth-2`'s defects — passed *more often*, an ordering that
cannot be a depth effect.

## The residual limit, stated carefully

`framing-2` deletes `models.py` and leaves `app.py` importing a name that no
longer exists. The model must recreate the file. Its five-round failures never
get past the gate:

```
round 1..5: exit 2 | 1 of 9 preconditions unmet.
```

and the cells that do get past it fail on precisely the parts the suite only
*implies*: `test_complaint_model_contract_is_preserved` (the `timestamp` default
must be timezone-aware) and `test_seed_complaint_count_is_preserved` (3–5 seed
complaints).

**Do not read this as "framing is the limit."** `framing-2` varies three things
at once against the depth fixtures: evidence shape (precondition manifest vs
failing assertions), defect identity, and — the one the numbers point at —
**authoring from an implied contract vs editing visible files**. A clean
crossing was never built. The honest statement is that the surviving difficulty
lives somewhere in that bundle, and the reconstruction reading is the one the
failure detail supports.

## Scope — read before quoting any number here

- **Fixture tier only.** This measures repair from a **pinned committed tree**,
  not repair inside the pipeline. Pinning is what makes the budget arm
  comparable at all. **Nothing here generalises to pipeline behaviour.**
- **n = 3 per cell, 24 cells.** Directional, not precise.
- **1 harness-void** (`depth-2/2/3`, `stop_reason=limit` — a runaway generation
  at the 8192-token output cap with two-thirds of the context unused). Recorded
  as a model-behaviour observation; the cell contributes no pass/fail.
- **No number from the 80-cell matrix or the v1–v3 ledgers enters this verdict.**
  They are harness archaeology.

## What this cost, and the lesson

The decisive fixture was named on day one — the 80-cell verdict's open-work item
9 called a multi-file repair fixture *"the only way to test what the whack-a-mole
brief actually asked about"* and §5 called it *"the cheap decisive test"*.
**Twenty-one loop iterations across two ledgers went by without building it**,
spent instead on perfecting the pipeline the question did not need. Building it
took one iteration; answering the question took two more, at roughly 90 minutes
of GPU.

The pattern worth keeping: **every substantive correction in this project came
from re-measuring, never from re-reading.** Four review passes over the same
prose left the errors intact; one ordering anomaly in a results table exposed the
directive defect that had been distorting every Mellum number for a month.

---

# Addendum — the clean framing arm (2026-08-26, same day)

The verdict above declined to call the residual limit "framing" because
`framing-2` confounded evidence shape with author-vs-edit.
`framing-2-edit` separates them: same two-file **edit**, nothing deleted, but
the suite aborts collection so the model sees a precondition manifest instead
of failing assertions. Pre-registered as 6 cells; `depth-2` is the comparator
and was not re-run.

## Result: evidence shape is not the limit. Authoring is.

| fixture | files | task | evidence | rounds=2 | rounds=5 | pooled |
|---|---|---|---|---|---|---|
| `depth-2` | 2 | edit | failing assertions | 2/2 valid | 2/3 | **4/5** |
| `framing-2-edit` | 2 | **edit** | **precondition manifest** | 2/3 | 3/3 | **5/6** |
| `framing-2` | 2 | **author + edit** | precondition manifest | 0/3 | 1/3 | **1/6** |

Holding files-to-fix and task type constant and varying **only** the evidence
shape moves the pass rate from 4/5 to 5/6 — no effect. Holding the evidence
shape constant and varying **only** author-vs-edit moves it from 5/6 to 1/6.

**The P17 verdict's careful reading is confirmed.** The surviving difficulty is
being asked to author a file whose required contents are only implied by the
tests, not how the failure surface is presented.

## What this says about the 80-cell verdict's original blame

That document blamed pytest collection aborts for burning the repair budget —
20 of 40 Mellum cells. **That blame was correct about the raw abort and has been
cured, not refuted.** A raw abort shows one opaque `ModuleNotFoundError`; the V2
fix replaces it with an enumerated manifest naming every unmet requirement:

```
  [MET]   from models import Complaint
  [UNMET] models.complaints -- AttributeError: module 'models' has no attribute 'complaints'
1 of 9 preconditions unmet.
```

`framing-2-edit` measures the *cured* state, and in that state a collection
abort costs nothing. **This experiment cannot compare against the raw abort** —
the manifest is unconditional in the current harness — so it is evidence that
the fix worked, not evidence that the original diagnosis was wrong.

## The one failure, and what it looks like

`framing-2-edit/2/2` emitted `models.py` twice and **never emitted `app.py`**:

```
turn 2: headings=['models.py']     round 1: validationFailed
turn 4: headings=['models.py']     round 2: exit 2, 1 of 9 preconditions unmet
```

Renaming the symbol in `models.py` without repairing the import in `app.py`
breaks the import, so round 1 fails validation and round 2 is back at the gate.
A half-done two-file fix — the whack-a-mole shape the brief described — but now
1 case in 6 rather than the norm.
