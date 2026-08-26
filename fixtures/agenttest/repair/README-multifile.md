# Multi-file repair fixtures (2026-08-26)

The 80-cell verdict named a multi-file repair fixture as **"the only way to test
what the whack-a-mole brief actually asked about"** (open-work item 9) and
**"the cheap decisive test"** (§5). It was never built. These are it.

**"Depth" counts FILES THAT MUST CHANGE, not failing assertions.** Measured
baselines:

| fixture | files to fix | assertions failing | evidence the model sees |
|---|---|---|---|
| `plausible-wrong-fix` | 1 | 1 | failing assertions |
| `depth-2` | 2 | **3** | failing assertions |
| `depth-3` | 3 | **4** | failing assertions |
| `framing-2` | 2 | — (collection abort) | precondition manifest |

depth-2 fails three assertions rather than two because dropping `lang="en"`
also trips `test_complaints_board_preserves_the_shared_layout`. Recorded rather
than tuned away: the arm measures files-to-change, and forcing a 1:1 mapping
would have meant a less natural defect.

## Why the depth fixtures stay importable

A defect in `models.complaints` aborts pytest collection (the suite reads it at
module level, `test_acceptance.py:26`), which **hides every other defect**. That
would confound depth with serialisation — the failure the whole P16 effort
exists to stop measuring. All three depth fixtures therefore keep the suite
importable, so every defect is visible from round 1.

## The defects

- **A — `app.py`**: `RedirectResponse("/complaints")` loses `status_code=303`
  → `test_post_complaint_redirects_to_complaints_board`.
- **B — `templates/base.html`**: `<html>` loses `lang="en"`
  → `test_home_html_element_declares_english_language` (+ shared-layout).
- **C — `models.py`**: `timestamp` default becomes naive `datetime.now`
  → `test_complaint_model_contract_is_preserved` (asserts `tzinfo is not None`).

`depth-2` = A+B. `depth-3` = A+B+C. Each defect is individually plausible —
none is a syntax error or an obvious typo.

## framing-2

The **framing** contrast: the same *two files must change*, but the evidence is
presented differently. `models.py` is deleted (via the `.delete` manifest) and
`app.py` imports `SEED_COMPLAINTS as complaints`, so the model must both
recreate `models.py` with a `complaints` list and repair `app.py`'s import.
Collection aborts, so the model is shown the precondition manifest
(`ModuleNotFoundError: No module named 'models'`) instead of failing assertions.

**Stated confound:** framing-2's defects are not the *same* defects as depth-2's,
so the framing arm varies evidence-shape and defect-identity together. A clean
crossing was not achievable cheaply. Any framing claim must say this out loud.
