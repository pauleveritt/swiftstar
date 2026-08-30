# P26 closure verdict: eval-system hygiene

**Date:** 2026-08-29
**Status:** reference — extracted verbatim from `ROADMAP.md`'s P26 Status
cell, which had grown to 3192 characters (cap 1000). Nothing here is new;
this is the trail `docs/sdd.md` says to move to `research/` and link, not
delete, when a cell blows its cap. `docs/sdd.md`'s own "Standing rules"
section cites this note by name as the second instance of a written
convention nothing checked getting ignored — keep this doc's account of the
gate failure intact even as the ROADMAP row above it shrinks.

**Complete (2026-08-29)**, corrected same day after being marked partial in
error — see below for what "one merged schema" actually meant.

## Done

1. The overturned flat-depth-profile claim is corrected in all three places
   the audit named (ROADMAP's Now-section narrative at the time, and the
   P13 and P17 rows).
2. The campaign scripts, manifests, and results are committed as the
   pre-registered evidence they are — the overnight set in `f61de85`, the
   five follow-up arms plus the failure classification in the branch that
   landed this row.

## The gate FAILED, not merely slipped

This phase's row said the schema freeze "should land before the next
campaign cell runs so that batch is comparable to the last." Five arms then
ran on 2026-08-29 *after* that row was written, without the freeze — and one
of the two schemas was **widened** in the process (an `arm` column added to
`run-experiment.py` for interleaved prompt arms). So the condition was not
just unmet, the gap grew, and that day's batch was already non-comparable to
the previous one in that dimension.

## Corrected 2026-08-29 (the row was stale)

Items (3) and (4) landed in `3dac58a` ("P26 (redo): de-duplicate cell
classification, flag the grader claim"), redone against current main after
the original worktree attempt went stale.

**(3) is closed, but not as a literal one-physical-schema merge** —
`run-experiment.py` still writes 7 columns and `run-orchestrate-campaign.py`
still writes 10, deliberately: `campaign_common.py`'s own docstring records
the call that forcing one column set would mean placeholder blanks in
whichever mode doesn't use a column (`dispatches`/`acceptance_exit`/`seconds`
have no fixture-mode analogue). What was actually unified — because it was
the actual site of the drift bug, not a legitimate schema difference — is the
closure/append logic: `done_cells` now takes a `key_columns` list of
`(index, default)` pairs, generalized enough to describe both the plain
3-column key and the 4-column key with a trailing optional `arm` (legacy rows
predate it and default to `'plural'`), so the exact kind of silent widening
that caused this gate to fail once (the `arm` column landing unaccounted-for)
is now absorbed by a documented default instead of repeating unnoticed.
Verified: a 7-case unit test (`Tools/test_campaign_common.py`, all passing)
plus a read-only `campaign-report.py` run against the real arm-widened
results file — no engine invoked.

**(4)** is flagged in
[`2026-08-27-p22-laguna-xs-acceptance-verdict.md`](2026-08-27-p22-laguna-xs-acceptance-verdict.md)
(where the P22 acceptance narrative now actually lives, moved there by an
intervening docs-reorg commit, not in this row as originally planned) — the
"grader verdict `good`" / "GLM 5.3... APPROVE" claims are marked as
`DeepSeekGrader`, an uncalibrated LLM judge, advisory pending calibration.

## Outcome

All four P26 "Now" items are done; the gate for the next campaign cell is
cleared. See
[`2026-08-29-eval-system-audit-and-later-work.md`](2026-08-29-eval-system-audit-and-later-work.md)
for the remaining non-gating Later work (Swift-native port, grader
calibration itself, second fixture app).
