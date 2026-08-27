# P22 — Laguna XS 2.1 acceptance verdict (overnight spike)

**Date:** 2026-08-27
**Phase:** P22 — More models: Laguna XS + model switching (Laguna XS arm)
**Status:** **acceptance done** — both agentclinic evals green on the real engine, `--ssd-streaming`
**Implementation:** branch `p13-laguna-xs-variant` (8 commits; spec
`docs/superpowers/specs/2026-08-26-p13-laguna-xs-variant-design.md`)

## What this document is

The official record of the spike that brought **Laguna XS 2.1** to parity with
Laguna S in SwiftStar: how the engine side was already merged, what SwiftStar
shipped, the live acceptance results, and the open items. The P22 roadmap row
is the pointer here.

## 1. The engine side was already merged (verified, not assumed)

Git archaeology + a read-only GLM 5.2 review (2026-08-26) confirmed the XS21
engine work — `DS4_VARIANT_LAGUNA_XS21`, `DS4_SHAPE_LAGUNA_XS21`,
`--ssd-streaming`, `--ssd-streaming-cache-experts`, `--prefill-chunk`, the
routed-expert Metal cache — is **already in the pinned fork**
(`external/ds4` @ `f56d0ca`; the XS line tip `bcf1b1c` is an ancestor of the
pin). The only engine-side delta left in the ds4 `laguna-s21-ssd` branch is one
6-line commit widening `--ssd-streaming` admission to **Laguna S 2.1** —
orthogonal to XS, deliberately out of scope. Upstream `antirez/ds4` has no XS21
line to reconcile.

So the spike was **SwiftStar-side plus verification**, not an engine merge.

## 2. What SwiftStar shipped (branch `p13-laguna-xs-variant`)

- **`laguna-xs-2.1` preset** in `VariantRegistry` (immediately choosable in the
  Settings picker): architecture `"laguna"`, rope yarn / 500000.0, quant
  contract `q3_k` down on layers 1–39 (dense layer 0 skipped via a new
  `QuantContract.startLayer`), memory budget 6.53 GiB @32k / 5.91 @16k,
  engine flags `--ssd-streaming --ssd-streaming-cache-experts 3200
  --prefill-chunk 4096`, model path overridable via `SWIFTSTAR_LAGUNA_XS_MODEL`.
- **Typed engine-flag wiring** (`EngineRuntimeConfig` on the `Variant`) threaded
  through `AgentCommand`/`ServerCommand`/`PoolEngine` argv and every spawn site
  (app controllers, `runDispatchedTurn`, both harness `AgentSettings` sites).
- `GGUFType.q3_k`, `laguna.rope.*` metadata keys, the `startLayer` verifier
  change, and the GLM 5.3 review fixes (pool-argv runtime test, Mellum
  `startLayer == 0` regression assertion).
- **614 fast-tier tests green** (was 600 at baseline). GLM 5.3 (read-only)
  review: **APPROVE**, all findings Minor, two folded in.

## 3. Live acceptance (real engine, `--ssd-streaming`)

Run headless via the canonical harness (`swiftstar-agenttest --variant
laguna-xs-2.1`), graded by the real 13-test acceptance suite.

**Smoke / load gate (also closed the open memory question):**
- XS21 loads and generates with `--ssd-streaming` in the pinned fork — clears
  the "merged ≠ verified-merged" caveat (GLM 5.2) for the load path.
- The engine's own `ready` event reported `planned_bytes = 7015923720` =
  **6.53 GiB**, exactly the declared budget (KV 1.31 + scratch 0.99 + resident
  0.20 + expert cache 4.03). **The ~6.1 GiB Laguna-S-resident scratch
  under-report does NOT apply to XS SSD-streaming** — its scratch is 0.99 GiB,
  so the ROADMAP's P3-correction concern does not carry over. Risk closed.

**Agentclinic basic (`--spec roadmap`):**

| config | result |
|---|---|
| default | **FAIL** — hit the 30-min wall-clock cap without initiating (rc=143) |
| `DS4_AGENT_TOOL_NUDGE=2` | **PASS** — 13/13, grader verdict `good`, 249s |

**Agentclinic user-story (`--spec roadmap-user-story`):**

| config | result |
|---|---|
| default | **PASS** — 13/13, grader verdict `good`, 331s |

Evidence per run: `captures/agenttest/20260827-074305-roadmap/` and
`captures/agenttest/20260827-074718-roadmap-user-story/` (`acceptance.txt`,
`verdict.json`, `run-config.json`, `wire.ndjson`, `wire.trace`).

## 4. Findings

1. **XS at Q3_K fails to initiate on the implementation-framed spec without the
   nudge lever.** `DS4_AGENT_TOOL_NUDGE=2` — the forcing function built during
   the Mellum/Laguna-S work ("nudge is necessary") — flipped `roadmap` from a
   30-min no-initiation timeout to a 13/13 pass in ~4 min.
2. **Framing matters as much as the quant.** The same model passed
   `roadmap-user-story` on the *default* config (331s) with no nudge — the
   user-story framing initiates without the forcing function.
3. **The engine line is production-ready at the load/steering level**: 6.53 GiB
   resident, SSD streaming live (cache 3200 experts, hit rate ~0.22 on the
   smoke prompt, mlock OK), generation at ~19 t/s on the M5 Max for a 2-token
   reply — enough to confirm the path, not a throughput claim.

## 5. Open items (honest, unchanged)

- **16 GB hardware acceptance still unconfirmed** — this spike ran on the
  128 GB dev machine; the ROADMAP "feasible, unconfirmed" status stands until
  mini-notes §7 passes on real 16 GB hardware.
- **XS golden recapture** (fixtures) — pending, per the standing recapture rule.
- **Model switching** (P22's woven-in forward work: the "Apply this model"
  action, pre-admitted before stop, switch refused mid-generation) — not built.
- **Branch unmerged** — `p13-laguna-xs-variant` (8 commits) is ready to merge;
  P22's forward items remain on the branch + this record.
- **SSD support across the Laguna line (S arm, forward)** — Laguna S still
  refuses `--ssd-streaming` (the pin's gate, `ds4.c:62233`, admits XS21 only).
  The enabling change already exists: commit `2613723` ("admit --ssd-streaming"
  for S 2.1, 6 lines) on the local `laguna-s21-ssd` branch in `~/projects/ds4`
  (not pushed, not in the fork). To share SSD support across the line: merge
  that commit into the fork's integration line → submodule bump → the standing
  golden-recapture gate; add a `laguna-s-2.1` Variant so the shared
  `EngineRuntimeConfig` carries the flags; then measure S-ssd's resident
  footprint (mini-notes §8 numbers are XS's, not S's), define the S-ssd target
  machine (32 GB?), and check DFlash × SSD-streaming interplay. S was
  deliberately excluded from SSD streaming (engine-lines.md), so this is an
  explicit re-scope, not a fix.
