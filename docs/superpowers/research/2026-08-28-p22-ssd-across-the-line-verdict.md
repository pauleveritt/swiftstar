# P22 SSD across the Laguna line — verdict

**2026-08-28.** P22's SSD-across-the-Laguna-line forward item closes: Laguna S
2.1 now spawns with `--ssd-streaming` through the shared `EngineRuntimeConfig`,
the engine's admission gate admits the whole Laguna line, and the footprint +
DFlash interplay are live-validated on the pinned engine. Engine divergence
#13; evidence: [`2026-08-28-p22-ssd-across-the-line-live-validation.md`](./2026-08-28-p22-ssd-across-the-line-live-validation.md).

## What shipped

1. **Engine (divergence #13, `849f375` on `p20-dispatch-schema`)** — a faithful
   port of the local `laguna-s21-ssd` branch's tip `2613723` against the pin:
   the `--ssd-streaming` admission gate widens from XS21-only to XS21 + S21.
   The `--prefill-chunk` gate stays XS21-only (XS's 4096 is XS-tuned; S
   declares no prefill chunk — the branch's deliberate scope). Fork-ledger
   row #13 written (why it exists + what retires it). Wire-neutral, so no
   golden recapture is owed (same precedent as divergence #12).
2. **SwiftStar (`7838700`)** — `VariantRegistry.lagunaS` gains
   `runtime: EngineRuntimeConfig(ssdStreaming: true,
   ssdStreamingCacheExperts: 3200, prefillChunk: nil)`; submodule bumped to
   `849f375`; the two tests that asserted S's nil runtime were updated to the
   new behavior (fast tier green, 741 tests). The variant change and the bump
   land in one commit so the app is never in the state "declares the flags the
   engine still refuses".
3. **The engine binary** rebuilt (`make ds4-agent`) with the new gate.

## Live validation (all on the real engine, Metal, M5 Max)

| Check | Result |
|---|---|
| S spawns with `--ssd-streaming --ssd-streaming-cache-experts 3200` | admitted; **22.04 GiB resident** vs 56.9 GiB resident (~35 GiB saved) at ctx 51200 |
| DFlash × SSD streaming | **loud refusal, exit 1**: "--ssd-streaming is not compatible with support models yet" — the exclusion composes (load-bearing for correctness) |
| DFlash alone (resident path) | admitted; 58.18 GiB plan incl. the Q8_0 draft; DFlash graph built; generated a turn |

## Binding items

- The ROADMAP P22 row's SSD forward item: **shipped** — Laguna S spawns with
  `--ssd-streaming` (variant runtime → argv, pinned by
  `AgentCommandTests.argvAppendsVariantRuntimeFlags` and proven live by the
  engine probe), footprint validated (22.04 GiB), fork-ledger row written,
  DFlash interplay validated both directions.
- Standing recapture rule: divergence #13 is wire-neutral (admission gate
  only) — no golden recapture owed, recorded in the ledger row and here. The
  bump gate = build + live spawn, both done.

## Open items (recorded, not blocking)

- The S-ssd expert-cache count (3200) mirrors XS's tuned value; the first
  footprint measurement (cache ≈ 12.97 GiB) is the baseline a future tuning
  pass re-measures against S's larger experts.
- 16 GB hardware acceptance — **skipped by decision 2026-08-27**, never
  scheduled.

## Review

The change is small and mechanical (a 4-line gate port + a variant runtime
declaration + test updates); the GLM review of the same session's
model-switching work (approve-with-minor, folds at `8d62c10`) covered the
shared wiring. The engine patch itself is a faithful re-application of a
previously-reviewed local commit (`2613723`), re-verified live here.
