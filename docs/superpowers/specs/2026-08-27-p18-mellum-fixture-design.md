# P18 — `mellum-fixture` benchmark design

**Date:** 2026-08-27 (relocated from ROADMAP.md's `## Now` section 2026-08-29,
content unchanged — see [`sdd.md`](../../sdd.md)'s rule that a design belongs
in `docs/superpowers/specs/`, not inline for a phase deferred to last).
**Phase:** P18 — `mellum-fixture` benchmark (deferred to the end of the phase
sequence; see the ROADMAP P18 row for current status, including the
2026-08-29 "job changed" note).

## P18's shape, deliberately boring

1. **Fixture-only, one task family per run.** Start with "repair visible
   files" (editing). Keep "author a missing file from implied tests" as a
   *separate* benchmark — P17 shows it is a different capability, not a harder
   version of the first.
2. **One attempt, no repair rounds, no prompt interventions.** A pinned broken
   tree, the writable files, an explicit task/acceptance contract. Capture
   output, apply it, grade it. Nothing self-modifying.
3. **A flat oracle**, not a collection-gated pytest run: 13 independently
   evaluable requirements, each pass/fail, even when imports fail. Pre-register
   both the primary metric (all 13 pass) and the secondary (count passed) —
   partial scores real from the start, not retrofitted after a binary metric
   turns out to have no resolution (as v5's did).
4. **Freeze the prompt and fixture manifest before sampling.** ~10–20
   fresh-process trials per fixture, shuffled across fixtures. Raw packet,
   engine argv, output, resulting tree, and requirement vector are the record.
   Never overwrite or rerun a recorded cell.
5. **Only then, as a separate bounded comparison**, test rounds: if one-shot
   results are stable, compare exactly one predeclared feedback policy (e.g.
   1 vs 3 rounds) on the same fixtures and oracle. No prompt tuning between
   arms.

**A new, standalone `mellum-fixture` runner, not an extension of
`swiftstar-agenttest`.** Near-zero policy: construct fixture → call Mellum →
apply output → independently score → save artifacts. It answers one narrow
question — what can this Mellum configuration do on explicit, pinned repair
tasks — and does not diagnose the pipeline, repair its own methodology, or turn
every surprising result into another feature.
