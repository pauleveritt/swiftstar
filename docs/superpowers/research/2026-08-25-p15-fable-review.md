# P15 — Fable review of the harvest result

*Independent review, 2026-08-25, against commits `1a8314a` and `05a4fcc`. The
reviewer reconstructed each capture from its own `wire.ndjson` and verified the
committed fixtures byte-for-byte before assessing the claims. Recorded here
verbatim in substance; the actions taken follow each item.*

## (a) Claims that did not fully hold

**Claim 1 was overstated in one particular.** The fixtures verified
byte-identical to the wire text of all four captures. But "three of the four
'failures' contained complete, EOS-terminated apps" is wrong for the `repeated`
capture: its `stop_reason` is `limit` (the 8192-token wall), not `eos`, and its
first pass emits only 4 of the granted files. Only the two `unfenced-*` captures
fit the "complete + EOS, lacking only fences" description. "Three of the four
failures" is also sloppy — there were only three failures. The replay tests
themselves are honest about both points.

> **Action:** corrected in the verdict record — two of three failures were
> fence-only; `171057` is separately classified as a stopping failure. The
> overstatement originated in the `1a8314a` commit message, which cannot be
> rewritten now; the record is the authority.

**Fixture-fidelity gap.** `HarvestCaptureReplayTests` used a 5-file allowlist
while the live packet grants 6 (including `models.py`), so the test's
`outOfGrantHeadings == ["models.py"]` assertion tested a grant the real runs
never used.

> **Action:** fixed. The replay now uses the real 6-file grant read from the
> captures' own `packet.json`; the fenced capture harvests 6 files with no
> out-of-grant heading, and the assertions were corrected to match.

**Claims 2, 3, 5, 6 verified** against source, diffs, and wire. **Claim 4
verified:** three runs' `acceptance.txt` show "13 passed"; the failing runs
aborted pre-grading; their wire contains genuine import defects
(`from .models import complaints`; `RedirectResponse` from the wrong module),
not harvest losses — both runs' texts carry full allowlisted headings.

## (b) The correctness risk of the lenient harvest

Without a fence, *anything* under an allowlisted heading becomes file content.
If the model writes prose under `#app.py`, the host writes that prose to disk;
in the repair arm it **overwrites a previously-working file**. Trailing junk
likewise glues onto the last file — already visible in `unfenced-b`, where the
`#uvicorn.run(...)` and `#uv run --project …` lines after `tests/test_app.py` are
appended into its body, harmless only because `#` is a Python comment. In an
`.html` grant they would render literally, and the import check never loads
templates.

**The blast radius is taxonomic as much as file-level.** Turns previously
classifiable as `contractNotFollowed` now silently become `validationFailed` or
acceptance failures, so the experiment can no longer distinguish "the model
ignored the contract" from "the model wrote buggy code" — the exact metric this
phase reports. First-occurrence-wins compounds it: a later self-corrected
re-emission is discarded in favor of the first draft.

> **Action:** recorded as limitation 3 in the verdict record, with the taxonomic
> point called out as the one that most constrains what the phase may claim. The
> 0-`contractNotFollowed` result is therefore stated as "the harvest stopped
> rejecting well-formed work," not "the model became compliant." Not fixed —
> any content-vs-prose discriminator would be a heuristic guard holding less
> information than the authoritative layer, which this codebase has explicitly
> rejected before.

## (c) Verdict

**CLOSE.** The core claim — host-controlled emission works, with fixtures and
captures checking out — is verified. The acknowledged gaps (the two-turn seam and
the repetition abort firing 0 times live, the prose-misclassification risk, no
phase-boundary repair) are documented follow-on work, not unverified load-bearing
evidence for this phase's conclusion.

## Reviewer items deliberately not actioned

- **Prose-vs-content discrimination.** See above; a heuristic guard is worse than
  the documented limitation.
- **First-occurrence-wins discarding a self-corrected re-emission.** Real, but
  changing it would mean trusting the *last* emission, which in the degenerate
  captures is truncated garbage. Left as-is with the tradeoff recorded.
