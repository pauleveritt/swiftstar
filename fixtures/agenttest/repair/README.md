# Repair fixtures

Bugs for testing the **repair** role, built to close two gaps the existing
repair evidence does not cover.

The repair result on record is 3/3 correct minimal fixes, 13/13 acceptance. It
was measured on two bugs — a wrong import path and a missing `default_factory` —
that share two properties which make them weak evidence:

1. **Both tracebacks quote the defective line.** A pytest `ImportError` prints
   `app.py:1: from fastapi import ... RedirectResponse` verbatim, so the model
   was never asked to *localize* a fault. This collapses the L1 ("diagnose from
   failure alone") and L2 ("+ the offending line") rungs of the
   [revision-test ladder](../../../docs/superpowers/research/2026-08-24-laguna-revision-test-spec.md)
   for that entire bug class.
2. **Both have a single canonical fix.** Nothing distinguishes a model that
   *revises* from one that *recites* a memorized correction.

Each fixture below is a minimal delta from `../reference/app.py`, fails exactly
one acceptance test (12/13), and is verified — the failure output and the
discriminating behavior below were produced by running the real suite, not
predicted.

## `misleading-locus/` — the traceback points away from the defect

**The bug.** The POST handler appends to a *copy* of the seed list:

```python
updated = complaints.copy()
updated.append(Complaint(agent_name=agent_name, text=text))
```

The write is silently discarded. Nothing raises.

**Fails:** `test_posted_complaint_appears_on_complaints_board` —
`assert 'Codex acceptance test' in '<!DOCTYPE html>…'`

**Why it is hard.** The failure surfaces at *rendering* — a string missing from
the complaints page — while the defect is in the *handler*. A model that repairs
what the traceback points at will edit `templates/complaints.html`, which is not
broken. The file picker in `repair.py` scores candidates by traceback-substring
match and would make exactly this mistake; it chose a non-broken file in three
observed rounds already.

**What it measures.** Localization from behavior rather than from a quoted line —
and, because `complaints.html` is genuinely innocent, whether a wrong repair is
detected as wrong.

## `plausible-wrong-fix/` — the obvious correction is incorrect

**The bug.** The redirect omits its status code:

```python
return RedirectResponse("/complaints")
```

FastAPI defaults to **307**; the contract requires **303**.

**Fails:** `test_post_complaint_redirects_to_complaints_board` — `assert 307 == 303`

**Why it is hard.** "Redirect status code" pattern-matches to **302 Found**, the
reflexive answer. Verified: applying 302 still fails (`assert 302 == 303`);
only 303 passes. So the fixture discriminates a model that reads the contract
from one that recalls a convention — which is the distinction the current
repair evidence cannot make.

**Pair it with the redaction gate.** The spec states 303 explicitly, so an
un-redacted run is an L3 cell (fix stated) wearing L1 clothes. For a genuine
diagnosis test, run with:

```
AGENTTEST_REDACT=303
```

The harness will then refuse to dispatch any packet that states the answer —
the same gate that caught `roadmap.md` shipping `default_factory` verbatim.

## Both fixtures are assertion-style

Neither traceback names the defective line, so **both are valid L1 cells** — the
first in this corpus. Failure at L1 here means "cannot localize from evidence,"
which is a real finding rather than an artifact of the bug class.

## Usage

Overlay onto the reference solution, then run the acceptance suite as the
harness does:

```bash
cp -r fixtures/agenttest/reference/* "$WORK/"
cp fixtures/agenttest/repair/<fixture>/app.py "$WORK/app.py"
cp fixtures/agenttest/acceptance/test_acceptance.py "$WORK/"
cd "$WORK" && uv run --project ~/projects/pauleveritt/local-ai-pi pytest -q test_acceptance.py
```

Baseline for both: **12 passed, 1 failed**. The reference solution is 13/13, so
any other count means the overlay is wrong, not the model.
