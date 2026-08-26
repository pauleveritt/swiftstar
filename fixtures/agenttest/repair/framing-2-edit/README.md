# framing-2-edit — the clean framing fixture

Built 2026-08-26 to answer [`questions.md`](../../../docs/superpowers/research/questions.md)
item 3. P17's `framing-2` confounded three things at once; this holds two of
them fixed.

## What it varies, and against what

Compare **only** against `depth-2`. Both require **exactly two file edits** and
neither requires authoring a file from scratch:

| fixture | files to fix | task | evidence the model is shown |
|---|---|---|---|
| `depth-2` | 2 | edit | 3 failing assertions |
| `framing-2-edit` | 2 | **edit** | precondition manifest, 1 unmet of 9 |
| `framing-2` (P17, superseded for this purpose) | 2 | **author + edit** | precondition manifest |

`framing-2` deleted `models.py`, so its failures measured reconstruction from an
implied contract — the P17 verdict's actual finding. `framing-2-edit` deletes
nothing.

## The defect

`models.py` renames its seed list `complaints` → `SEED_COMPLAINTS`; `app.py`
imports `SEED_COMPLAINTS as complaints`. Both files are internally coherent and
**the application itself runs**:

```
$ python -c "import app; print(app.app is not None)"
app imports OK: True
```

Only the *contract* is broken: the suite reads `models.complaints` at module
level (`test_acceptance.py:26`), so collection aborts and the model is shown

```
  [MET]   from models import Complaint
  [UNMET] models.complaints -- AttributeError: module 'models' has no attribute 'complaints'
1 of 9 preconditions unmet.
```

The fix is two edits — rename in `models.py`, update the import in `app.py`.

## Confounds, stated

- **Defect identity still differs** from `depth-2`. This is unavoidable: the
  same defect cannot both abort collection and not abort it.
- **Signal count differs** — 3 failing assertions vs 1 unmet precondition. That
  is not a confound but the mechanism under test: a collection abort *compresses
  the whole failure surface to a single gate*, which is precisely what the
  80-cell verdict blamed for burning the repair budget.
