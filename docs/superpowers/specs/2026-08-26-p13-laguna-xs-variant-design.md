# SwiftStar P13 — Laguna XS 2.1 as a first-class variant

**Date:** 2026-08-26
**Status:** spec + implementation (this overnight spike); live acceptance pending the scheduled headless run
**Phase:** P13 — More models, Laguna XS arm (the "one more `Variant` instance next week" item deferred from `2026-08-25-p13-mellum-variant-design.md`).

## Problem

P13's Mellum arm shipped the `Variant` machinery (`Variant`, `RuntimeContract`,
`VariantRegistry`, `VariantResolver`, `VariantGate`, `VariantVerifier`,
`GGUFMetadataReader`, `MemoryBudget`) and one preset (`mellum-2.1`). The Laguna
XS arm was deferred. The task is to make **Laguna XS 2.1** a first-class,
choosable preset in SwiftStar at parity with Laguna S 2.1.

**A git investigation (independently re-confirmed by GLM 5.2, read-only) found
the engine-side work is already merged.** The XS21 engine effort
(`DS4_VARIANT_LAGUNA_XS21`, `DS4_SHAPE_LAGUNA_XS21`, `--ssd-streaming`,
`--ssd-streaming-cache-experts`, `--prefill-chunk`, the routed-expert Metal
cache) is in the fork SwiftStar pins (`external/ds4` @ `f56d0ca`): the XS line
tip `bcf1b1c` is an ancestor of the pin. The only engine-side delta left in the
`laguna-s21-ssd` branch is one 6-line commit (`2613723`) that widens
`--ssd-streaming` admission to **Laguna S 2.1** — orthogonal to XS, out of
scope. Upstream `antirez/ds4` has no XS21 line to reconcile.

So the remaining work is **SwiftStar-side plus verification**: a `Variant`, the
engine-argv wiring, and a live acceptance run that proves the merged code still
builds and runs (GLM 5.2's "merged ≠ verified-merged" caveat).

## Scope

**In:** `ModelFamily.lagunaXS`; the `laguna-xs-2.1` preset in `VariantRegistry`
(visible in the Settings picker immediately); `GGUFType.q3_k`; `laguna.rope.*`
key support in `GGUFMetadataReader`; `QuantContract.startLayer` (XS's routed
experts skip the dense layer 0); a typed `EngineRuntimeConfig` on the `Variant`
wired through `AgentCommand`/`ServerCommand` argv (which covers the
`PoolEngine`/harness spawn via delegation); the three launch sites in
`swiftstar-agenttest`/the controllers; unit tests; the live headless acceptance
run.

**Out:** the `2613723` S21-streaming commit (orthogonal; would trigger the
recapture gate for no XS benefit); upstream reconciliation (none exists);
a Settings download row for XS (the `RoutedQ3_K-biased` artifact is locally
quantized from BF16 — it has no public download URL); the 16 GB hardware
acceptance (this machine is 128 GB); the steering profile and sampler-flag
wiring (still deferred, as in the Mellum spec).

## Gardenable facts (verified against the artifact + ds4 source)

- **Artifact:** `laguna-xs-2.1-RoutedQ3_K-biased.gguf` (15.0 GiB on disk),
  locally quantized from `Laguna-XS-2.1-BF16.gguf` (poolside). GGUF v3,
  678 tensors, 60 metadata keys.
- **Tensor layout (read from the file):** 117 routed-expert tensors
  (`blk.N.ffn_{down,up,gate}_exps.weight`, layers 1–39) are **Q3_K**; the rest
  (attention, dense FFN, shared experts) are **Q8_0**; norms/biases/`exp_probs_b`
  are **F32**. "RoutedQ3_K" = routed experts Q3_K, everything else Q8_0.
- **Architecture:** `general.architecture = "laguna"`.
- **Rope:** `laguna.rope.scaling.type = "yarn"`, `laguna.rope.freq_base =
  500000.0` (also `freq_base_swa 10000`, `scaling.factor 32.0`,
  `original_context_length 8192`). The two load-bearing facts for the verifier
  are scaling type + freq base.
- **Resident footprint (SSD streaming, measured on 32 GB M1 Pro, mini-notes
  §8):** ctx 32768 → `KV 1.31 + buffers 0.99 + resident 0.20 + expert cache
  4.03 = 6.53 GiB` planned; ctx 16384 → `5.91 GiB`. The fixed non-KV part is
  5.22 GiB (= 4.03 + 0.99 + 0.20); KV is 0.69 (16k) → 1.31 (32k). The 6.53 GiB
  is the **resident** footprint, not the 15 GiB on-disk size.
- **Shipping command:** `--ssd-streaming --ssd-streaming-cache-experts 3200
  --prefill-chunk 4096 -c 32768` (LAGUNA-XS21.md §6). The variant declares the
  three SSD flags; context is the app's existing `-c`.
- **Sampler (family default, declared not wired):** temp 0.7, top-k 20, top-p
  0.95, min-p 0.05 (engine-lines.md).

## Design

### Components (all in `SwiftStarKit` unless noted)

1. **`ModelFamily`** — add `.lagunaXS`.
2. **`GGUFType`** — add `.q3_k` (id 11) + name case.
3. **`GGUFMetadataReader`** — also read `laguna.rope.scaling.type` /
   `laguna.rope.freq_base` (currently `mellum.rope.*` only). A file carries one
   family's keys, so there is no ambiguity.
4. **`QuantContract`** — add `startLayer: Int = 0`; the verifier iterates
   `startLayer..<layerCount`. Mellum unchanged (startLayer 0).
5. **`EngineRuntimeConfig`** (new) — the launch-time engine flags a variant
   needs: `ssdStreaming: Bool`, `ssdStreamingCacheExperts: Int?`,
   `prefillChunk: Int?`, with `argvFlags: [String]` that both argv builders
   append. This is the wired analog of `SamplerDefaults` (which is declared but
   unwired).
6. **`Variant.runtime: EngineRuntimeConfig?`** — nil = no extra engine flags
   (Mellum, custom paths).
7. **`AgentCommand.argv` / `ServerCommand.argv`** — append
   `settings.runtime?.argvFlags ?? []` after the base flags.
   `PoolEngine.argv` delegates to `AgentCommand.argv`, so the harness pool path
   is covered without a separate change.
8. **`AgentSettings.runtime` / `EngineSettings.runtime`** — carry the config
   from variant selection to argv. Callers: `AgentController.defaultSettings()`
   and `runDispatchedTurn` (`runtime: baseSettings.runtime`),
   `EngineController.defaultSettings()`, and both `AgentSettings(...)` sites in
   `swiftstar-agenttest/main.swift` (`runtime: resolvedVariant?.runtime`).
9. **`VariantRegistry.lagunaXS`** — the preset (constants below); appended to
   `all`, so the existing Settings picker shows it immediately.

### The XS contract (exact)

- `id: "laguna-xs-2.1"`, `displayName: "Laguna XS 2.1"`, `family: .lagunaXS`.
- `modelFile`: `~/models/laguna-xs-2.1-RoutedQ3_K-biased.gguf`, overridable via
  `SWIFTSTAR_LAGUNA_XS_MODEL` (mirrors `SWIFTSTAR_MELLUM_MODEL`).
- `sampler`: temp 0.7 / top-k 20 / top-p 0.95 / min-p 0.05 (declared, not
  wired).
- `runtime`: `EngineRuntimeConfig(ssdStreaming: true, ssdStreamingCacheExperts:
  3200, prefillChunk: 4096)`.
- `contract.architecture`: `"laguna"`; `rope`: yarn / 500000.0.
- `contract.quantLayout`: `.q3_k`, `startLayer: 1`, `layerCount: 40`,
  pattern `blk.%d.ffn_down_exps.weight` (39 sparse layers).
- `contract.memoryBudget`: `weightsGiB 5.22` (resident non-KV), `scratchGiB 0`,
  `kvGiBAt16k 0.69` / `kvGiBAt32k 1.31` / `kvGiBAt40k 1.31` (dead anchor),
  `minContext 16384`, `maxContext 32768`.

### Data flow

Unchanged from Mellum: pick "Laguna XS 2.1" → `VariantResolver.resolveVariant`
→ `VariantGate.admit` (read → verify → memory check at the selected context) →
spawn with argv that now carries the SSD flags. The harness gates once at the
top of `main.swift` with `contextSize: 32_768` (already in range).

### Error handling

Reused. Two notes:

- Selecting XS with the Settings context default (51200) refuses loudly:
  `context size 51200 is unsupported for this variant (supported 16384–32768)`.
  That is the correct baseline (mirrors Mellum D4); an auto-clamp-on-select is
  a possible later nicety, not this phase.
- The memory budget is the **declared** floor (D4/I1), so the variant path does
  not run `Feasibility.check`'s ~6.1 GiB Laguna scratch correction. See Open
  risks.

### Testing

- `VariantRegistryTests`: `resolve("laguna-xs-2.1")` returns the exact
  contract/runtime constants above.
- `VariantVerifierTests`: a crafted Laguna metadata — clean admit; wrong
  architecture/rope/down-quant named; a missing layer 1–39 named; layer 0 is
  *not* checked (startLayer 1).
- `GGUFMetadataReaderTests`: `laguna.rope.*` keys parse; `q3_k` type id maps.
- `AgentCommandTests` / `ServerCommandTests`: `runtime` emits exactly the three
  SSD flags; nil runtime emits none (byte-identical to today).

## Decisions

- **D1** — engine flags are a typed `EngineRuntimeConfig` on the `Variant`, not
  raw argv strings and not family-keyed logic in the builders.
- **D2** — `runtime` lives on `AgentSettings`/`EngineSettings`, so argv builders
  stay pure functions of settings; `PoolEngine` inherits via delegation.
- **D3** — the verifier's quant fact for XS is `ffn_down_exps == Q3_K` over
  layers 1–39 (the "RoutedQ3_K" contract), skipping dense layer 0 via the new
  `startLayer`. Architecture + rope are checked exactly as Mellum.
- **D4** — XS's declared budget is the measured resident footprint (6.53 GiB @
  32k); supported context is [16384, 32768]. `weightsGiB` here means *resident
  non-KV footprint* (expert cache + buffers + resident), not on-disk size.
- **D5** — the preset's default path is env-overridable (`SWIFTSTAR_LAGUNA_XS_MODEL`),
  so the live run can point at the local artifact without moving files.

## Verification (overnight sequence)

1. `swift test` — fast tier (unit + integration against fakes), green.
2. `make ds4-server ds4-agent` in the pinned fork — proves XS21 still compiles
   in the integration line (GLM 5.2's caveat).
3. Smoke: `ds4-agent -m laguna-xs-2.1-RoutedQ3_K-biased.gguf --ssd-streaming
   --ssd-streaming-cache-experts 3200 --prefill-chunk 4096 -c 32768` — proves it
   loads and generates.
4. Live headless acceptance: `swift run swiftstar-agenttest --variant
   laguna-xs-2.1 --spec roadmap` with `SWIFTSTAR_LAGUNA_XS_MODEL` pointed at the
   artifact — the gate runs up front, then the run records run-config + the
   observed footprint.
5. GLM 5.3 read-only review of the implementation diff; fixes applied.

## Open risks (recorded honestly, not resolved here)

- **`merged ≠ verified-merged`:** between `bcf1b1c` and the pin, upstream
  `main` merges churned `ssd_streaming`/prefill code. The build + smoke + live
  run are the proof; they cannot run before the scheduled window.
- **The ~6.1 GiB Laguna scratch under-report** (`Feasibility.lagunaScratchUnderreportBytes`)
  is keyed to Laguna S *resident*; whether it applies to XS SSD streaming is
  unknown. The declared 6.53 GiB is the engine's own measured breakdown; if the
  live run reports a materially larger resident footprint, the budget must be
  corrected before XS is trusted at 16 GB.
- **16 GB hardware acceptance still open** — this machine is 128 GB; the
  "feasible, unconfirmed" ROADMAP status stands until mini-notes §7 passes on
  real 16 GB hardware.
