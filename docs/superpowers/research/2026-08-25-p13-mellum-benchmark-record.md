# P13 Mellum benchmark — live-model verification record

**Date:** 2026-08-25
**What ran:** `swiftstar-agenttest --variant mellum-2.1 --spec roadmap` across a
path-presentation × nudge × seed matrix.
**Model:** Mellum 2.1, the 9.33 GiB shipping artifact
(`~/models/mellum-thinking-TARGET.gguf`).

## The variant machinery works end to end

- **Gate admitted the real artifact.** `VariantGate.admit` parsed the actual
  9.33 GiB GGUF (magic `GGUF` v3, 339 tensors) and verified architecture
  `mellum`, rope `yarn`@`500000.0`, and 28 Q8_0 down tensors — ADMIT, no
  crafted fixture.
- **Model loaded on the engine built from the pinned submodule** `f56d0ca`
  (the Mellum-loadable merge; the previously-built binaries predated it and
  were rebuilt first). Engine reported `resident model 9.33 GiB`, `9.99 GiB
  planned` at ctx=32768 — consistent with the declared `MemoryBudget`
  (9.33 weights + ~0.4 scratch + 0.48 KV ≈ 10.2 GiB).
- **`run-config.json` is self-describing** (I2/I7): `variant`, `sampler`,
  `seed`, `availableBytesGiB`, model path, think mode, tool budget.

## The competence floor (D9) was not met

| arm | seed | tool events | files | text chars | stop |
|-----|------|-------------|-------|-----------|------|
| relative | — | **0** | 0 | ~348 tok | eos |
| absolute | — | **0** | 0 | ~899 tok | eos |
| absolute + nudge=2 | 1 | **0** | 0 | 557 | eos |
| absolute + nudge=2 | 2 | **0** | 0 | 4241 | eos |
| absolute + nudge=2 | 3 | **0** | 0 | 625 | eos |
| relative + nudge=2 | 1 | **0** | 0 | 588 | eos |

Every arm ended in `validationFailed` on an **empty candidate tree** (the
`sha256:e3b0c44…` digest is the empty tree): Mellum narrated a complete,
correct-in-content solution — including the exact `uv run … pytest` commands —
and stopped without ever emitting a tool call or writing a file.

## The 2×2 is complete, and stochasticity is controlled

The current-harness path × nudge matrix is now filled (the relative+nudge cell
is no longer borrowed from B8):

| | nudge=0 | nudge=2 |
|---|---|---|
| relative | 0 calls | **0 calls** |
| absolute | 0 calls | **0 calls** (3 seeds) |

The three absolute+nudge seeds differ substantially in narration length (557 /
4241 / 625 chars) — proof the runs *are* stochastic at temp 0.6, not frozen —
yet **all** produce 0 tool calls. So the initiation failure is stable across
seeds, not a single-seed fluke. B8's optimistic cell (absolute → 6 calls, 4/4
files) does not replicate in the current harness under any tested combination.

## Sampling: default is correct, not a misconfiguration

GLM 5.2's next-step review flagged the sampler as an open confound. Checking the
source: Mellum's engine default is `ds4_engine_sampling_defaults` (ds4.c:63358)
— **temp 0.6, top-k 20, top-p 0.95, min-p 0.0**, JetBrains' published tool-call
setting, explicitly chosen over the generic 1.0/1.0 because that "is a poor
setting for a model expected to emit well-formed JSON tool calls." So the
0-call behavior is **not a misconfigured-default artifact** — the model is
running at its published sampler. (Whether a *different* sampler would initiate
remains an open, out-of-scope question; the published default is the correct
baseline, and the seed sweep shows initiation is 0 across the default's own
stochasticity.)

## Verdict

Per D9's failure policy (no initiation ⇒ Mellum is not shipped as a preset and
P13-Mellum blocks), **the competence gate fails: Mellum fails SwiftStar's
initiation gate reliably under the tested harness** (path presentation × nudge
× seed, at the published sampler). This is strong and sufficient to block
shipping; it is *not* a claim that "Mellum's agent competence definitively
fails" in the absolute — that is a broader claim these runs do not make. The
variant plumbing is complete and correct. The durable lever is the out-of-phase
harness work (the P9/P10 host-controlled action mode — declared objectives,
host-reported state, never-trust-claimed-test-results) — not P13 scope.
