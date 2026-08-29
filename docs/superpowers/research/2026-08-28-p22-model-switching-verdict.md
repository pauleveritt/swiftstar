# P22 model switching verdict — "Apply this model"

**2026-08-28.** P22's model-switching forward item closes: the "Apply this
model" action is landed, fast-tier tested, GLM-reviewed, and live-validated on
the pinned engine. Spec:
[`2026-08-28-p22-model-switching-design.md`](../specs/2026-08-28-p22-model-switching-design.md).
Evidence: [`2026-08-28-p22-model-switching-live-validation.md`](./2026-08-28-p22-model-switching-live-validation.md).

## What shipped

1. **`ModelSwitchEvaluator.decide`** (SwiftStarKit, pure, 9 fast-tier tests) —
   the single source of truth for the switch: `isGenerating` → refusal;
   same model file → `.noChange`; then admission (`.admitted`/custom →
   `.apply`; `.contractMismatch`/`.infeasible` → `.refused(reason)`).
2. **`AgentController.applyModelSelection()`** — resolves the staged selection
   exactly as the next spawn would (`AgentDefaultSettings.resolve`: context
   clamped to the target variant's range, variant `runtime` flags carried),
   runs the gate **before any stop**, and calls `restartAgent()` only on
   `.apply`. Refusals/no-ops surface as transcript system rows.
3. **Toolbar "Apply this model" item** in the model menu (visible while the
   agent is up; menu stays disabled mid-generation; idle help text updated).
4. **GLM 5.3 review fixes** — the shared `admitStagedVariant(contextSize:)`
   helper (one admission path for `startAgent` + `applyModelSelection`, so
   the two call sites cannot drift) and a same-file contract-mismatch
   no-change test.

Commits: `6c6f1fe`, `d299fa8`, `c450e60`, `8d62c10`. Fast tier: 741 tests,
106 suites, green.

## Binding-rule checklist (all evidenced live)

| Rule | Evidence |
|---|---|
| 1. Admission before stop; never kill a working session for an infeasible target | live: contract-mismatch refusal left the engine pid, capture dir, and `Ready` state untouched |
| 2. Refuse mid-generation | menu `.disabled(isGenerating)` + pure rule pinned by test |
| 3. Transcript preserved | live: all prior turns visible in the UI tree after two real switches |
| 4. Provenance per spawn reflects the new model | live: per-spawn `provenance.md` + per-turn `TurnOutcome.model` (SWIFTSTAR_LOG) across S → XS → DeepSeek |
| 5. Pool re-spawns with the new model | live: `--subagent-pool 2` in the XS spawn argv |

## Live validation summary (full record in the evidence doc)

- **S → XS**: in-process stop + re-spawn (app pid unchanged); new spawn argv:
  XS model, ctx clamped 51200→32768, `--ssd-streaming ... --prefill-chunk
  4096`, `--subagent-pool 2`; new provenance names the XS file; XS turn's
  outcome model = XS file; XS `ready` plan 6.53 GiB (the declared budget).
- **XS → DeepSeek** (accidental but real; the refusal lever was mathematically
  wrong — see evidence §4): admitted at 92.03 GiB under the Metal ceiling —
  **live proof of the P25 Cycle 4b denominator through the app** (the old
  free+inactive-pages denominator would have refused it). Turn completed;
  transcript preserved.
- **Refused switch**: env-mapped XS→Mellum contract mismatch → readable
  refusal system row; session untouched (rule 1).

## Decisions recorded

- The infeasibility lever for the live refusal test was wrong on this machine
  (no registry variant is infeasible at any allowed context on 128 GB —
  DeepSeek maxes at ~105.8 GiB vs the 107.52 GiB ceiling); the contract-
  mismatch lever exercises the same refusal wiring. The infeasible message
  path stays pinned by fast-tier tests.
- The DeepSeek switch needing P25's variant is moot: P25 landed 2026-08-28,
  so DeepSeek rides the same path as any registry variant (demonstrated
  live).

## Remaining open items (P22 row, unchanged)

- **XS golden recapture** — pending, per the standing recapture rule.
- **SSD across the Laguna line** — engine patch `2613723` → divergence row →
  recapture → `laguna-s-2.1` variant → S-ssd footprint + DFlash validation.
- 16 GB hardware acceptance — **skipped by decision 2026-08-27**, never
  scheduled.

## Review

GLM 5.3 (read-only, `fda614c..8d62c10`): **approve with minor fixes** — none
Critical/Important; both minors folded (`8d62c10`). The review's pending
"live validation" caveat is now closed by this record.

## Correctness fixes shipped 2026-08-28 (post-ship deep review)

A deep multi-angle code review of the full P22 commit range found the pure
`ModelSwitchEvaluator` sound but its wiring leaking in seven ways:

1. An empty stored `selectedVariantID` (written by the menu's own
   Default/Custom buttons) silently skipped both the admission gate and the
   SSD-streaming runtime.
2. `noChange` compared only the model file, so a same-file switch that only
   changed context size or runtime flags was swallowed as a no-op (and a
   symlinked path spelling forced a spurious restart in the other direction).
3. A custom/unverified model path bypassed admission entirely, killing a
   working session for a missing or infeasible target.
4. "Apply this model" was reachable mid-`/chat`-consult with no refusal.
5. The admitted target wasn't pinned across `restartAgent()`'s async stop
   window (TOCTOU).
6. The restart poll had no timeout.
7. The apply path wrote no transcript row, and a `.failed` launch was a
   main-window dead end with no recovery control.

All seven fixed: the pinned target is threaded through
`startAgent`/`restartAgent`, `noChange` does a full-settings + symlink-aware
comparison, a consult guard was added, custom paths get an existence check,
the restart poll is bounded, and `.failed` state gets a "Start with this
model" recovery control. Fast tier still green (744 tests).
