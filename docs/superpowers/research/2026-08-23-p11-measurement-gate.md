# P11 measurement gate — canonical arm (2026-08-23)

> **Superseded as a live finding** by [`2026-08-25-local-model-agency.md`](2026-08-25-local-model-agency.md). Retained as the evidence record for the two canonical-arm wall-clock runs (3.70x, 3.16x realized win) and the status-mislabeling and tokenization caveats.

**Status:** canonical arm measured. The sensitivity envelope (taskText bloat
×1.5/×2, failure injection, packet-count sweep) is a follow-up pass of the same
driver; the canonical number below is the headline D11(a) overhead ratio.
**Date:** 2026-08-23

The gate measures the realized context-curve win the whole phase was bought
for: does splitting one deep context into several shallow contexts actually win,
and by how much, versus the analytic 4.2x ceiling
(`docs/superpowers/research/2026-08-22-p11-engine-constraints-and-corrections.md`)?

## Command

```bash
bash Tools/p11-gate.sh   # SWIFTSTAR_MODEL / DEEP_CTX / POOL_CTX / WORKERS override defaults
```

It drives the real engine twice: one deep session (`-c 131072`) prefilling a
~116k-token corpus as a single prompt, and one pool (`-c 16384 --subagent-pool 9`,
8 workers + orchestrator) prefilling the same corpus as 8 sequential ~13.4k-token
`PoolPrompt`s to workers 1–8. Wall-clock is the wire's `ts` span.

## Measured (canonical arm)

| Side | Wall-clock |
|---|---|
| Deep (one 131k session, ~116k-token prefill) | **1550.4 s** (~26 min) |
| Pool (8 workers × ~13.4k-token prefill, sequential) | **419.1 s** (~7 min) |
| **Realized win** | **3.70x** (wall-clock) |
| Ceiling | 4.2x (analytic upper bound) |
| **Overhead ratio (D11a)** | **0.88** |

## Second run (2026-08-23, after the Kimi K3 fixes)

A second canonical run, after the correctness fixes, gave **deep 1427.9 s / pool
451.9 s = 3.16x realized** (overhead ratio 0.75). Across the two runs the
realized win is **~3.2–3.7x** — the ~0.5x spread is run-to-run prefill-rate
variation and thermal state (the 25-minute deep arm sustains load far longer
than the 7-minute pool arm). Both runs sit clearly below the 4.2x ceiling and
clearly above 1.0x: the pool wins, and the win is real but smaller than the
analytic bound — the expected result.

The prefill-only estimate is ~3.28x (deep prefill 1520.4 s from `status`
events; pool prefill ~8 × ~58 s). The wall-clock 3.70x is the honest "does the
pool win" number — it includes generate and load overhead, which the analytic
ceiling does not, and is why the realized win sits below 4.2x. **This is the
expected result, not a defect**: 4.2x prices two context *shapes*, not one task
done two ways; the shared preamble repeats per worker and results fold back, so
the real gain is materially lower — exactly what the gate exists to measure.

## Caveats (recorded, not hidden)

1. **Worker-status mislabeling.** The pool wire's `status` events are tagged
   with the *last-submitted* worker, not the *generating* worker — the loop's
   status emitter keys off `active_worker`, which the prompt router advances to
   the newest prompt while earlier workers are still running (serialized). The
   turns are correct; only the `status` attribution is wrong. It prevented a
   clean per-worker prefill measurement, which is why wall-clock is the primary
   metric. Fix: emit status for the worker whose state is `prefill`/`generating`,
   not `active_worker`.
2. **Chunk tokenization.** The ~500 KB corpus tokenized to ~116k tokens
   (≈4.3 chars/tok), not the 131k the ceiling prices; the deep run therefore
   prefilled ~116k, and the deep time is correspondingly shorter than the
   research note's 2,121 s extrapolation.
