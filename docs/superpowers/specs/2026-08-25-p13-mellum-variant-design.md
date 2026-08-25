# SwiftStar P13 design: Mellum 2.1 as a first-class variant

**Date:** 2026-08-25
**Status:** accepted (brainstormed; decisions D1–D9 approved in-session; reviewed by GLM 5.2 — findings C1–C3, I1–I7, M1–M6 folded in)
**Phase:** P13 — More models, Mellum arm.

This spec is the authority on *how* P13's Mellum arm is done. Scope is strict:
ship Mellum 2.1 as a first-class `Variant` in SwiftStar with an enforced
runtime contract, and gate it with a live-model benchmark. No fixtures, no
oracle chain, no ds4 engine work, no steering profile.

## Problem

SwiftStar has no notion of a model beyond a bare `@AppStorage("modelPath")`
string, a file picker, and a hardcoded Laguna default duplicated in
`EngineController.defaultSettings()` and `AgentController.defaultSettings()`.
"Which model am I running" is ambient state; "what does this model need" is
tribal knowledge scattered across the ROADMAP and research notes. Two findings
make that knowledge load-bearing:

1. **The runtime contract is part of the model.** A rope export alone flipped a
   greedy token at 26 tokens on identical weights (engine-lines harvest). The
   Mellum decode contract silently ran the Q8_0 kernel over foreign bytes when
   the down tensor was non-Q8_0 (P12.2). Both were *silently wrong, no error*.
2. **The engine's own admission is the only guard today**, and it fires at
   *load* — after a ~10 GiB model open — not at *selection*.

P13 fixes this by making a `Variant` a first-class value that owns its runtime
contract and is verified before anything expensive happens. The contract gate
protects **preset variants**; custom/raw file paths are the pre-existing
unverified path, surfaced as such (D7) — never silently treated as verified.

## Scope (strict)

**In:** `Variant` + `RuntimeContract` + `VariantRegistry`; `GGUFMetadataReader`;
`VariantVerifier`; `VariantGate` + `VariantResolver`; per-variant memory gating
(as a function of context size); Settings picker + controller wiring;
`swiftstar-agenttest --variant`; the live-model benchmark as acceptance; unit
tests.

**Out (explicit):** the steering profile (a future `Variant` field telling the
packet writer how broad/detailed to write and how much to micromanage — future
work, one-line note only); Mellum-shaped golden captures; the Q4_K oracle chain;
any ds4 engine work (Q4_K expert-major prefill, `planned_bytes` fixes — the
Mellum memory fix is already merged); the Laguna XS instance (next week);
sampler-flag wiring into argv; gating custom/raw file paths (they are declared
*unverifiable*, not silently verified).

## Gardenable facts (verified against source)

- **Wire does not carry rope/quant.** `hello` = version + capabilities;
  `ready` = `planned_bytes` (+ `ctx_used`/`generated`/`stop_reason`). Swift has
  no GGUF parser today. GGUF v3 metadata (header + kv + tensor directory) is
  fully specified by the P12.2 generator and is read without touching weights.
- **The shipping artifact is GGUF v3.** Verified against the real file
  `~/models/mellum-thinking-TARGET.gguf`: magic `GGUF` (`0x47475546`), version
  `3`, `n_tensors` = 339 (= 28 layers × 12 + token_embd/output_norm/output).
- **GGUF type ids** (`gguf_types[]`, ds4.c): `q8_0 = 8`, `q4_k = 12`,
  `q5_0 = 6`, `q8_1 = 9`.
- **Mellum tensor names** (`required_tensorf`, ds4.c:6599+): `blk.%u.
  ffn_down_exps.weight` (also `ffn_gate_exps.weight`, `ffn_up_exps.weight`) for
  layer indices 0..27.
- **Mellum rope contract** (`DS4_SHAPE_MELLUM2`, ds4.c): yarn scaling,
  `freq_base = 500000.0`, `freq_base_swa = 500000.0`, `scale_factor = 16.0`,
  `yarn_beta_fast = 32.0`, `yarn_beta_slow = 1.0`, `yarn_attn_factor =
  1.2772589`, `orig_ctx = 8192`, `context_length = 131072`. GGUF keys
  `mellum.rope.scaling.type = "yarn"`, `mellum.rope.freq_base = 500000.0`
  (P12.2 spec) are the two load-bearing ones.
- **Down is Q8_0 everywhere** on the shipping artifact (Q4_K gate/up on layers
  0–21, Q8_0 elsewhere). The engine's P12.2 admission refuses non-Q8_0 down at
  load. The Swift verifier checks the same rule at selection (before load).
- **Sampler defaults are family-level in the engine** (`--temp/--top-k/--top-p/
  --min-p` exist; help documents GLM and Laguna defaults but **not** Mellum's).
  So Mellum's sampler defaults are engine-determined and undocumented; P13
  declares them optional and records the source in the capture (D6).
- **Memory:** the shipping artifact is 9.33 GiB weights; KV is 0.26 / 0.48 /
  0.59 GiB at 16k / 32k / 40k context (overnight consolidation B1); scratch
  ~0.4 GiB (KV + scratch ≈ 0.9–1.0 GiB at 40k, A1). Total ≈ 10.3 GiB at 40k.
- **Feasibility today** (`Feasibility.check`) applies a Laguna-only scratch
  correction keyed by `modelName.contains("laguna")`; it uses the *persisted*
  engine plan, so a first run has no plan to refuse on. A declared per-variant
  budget closes that gap.
- **`EngineFailure`** already has `.infeasible(String)` (pre-spawn refusal,
  computed message). A variant-contract refusal adds `.variantMismatch(String)`.

## Design

### Components (all in `SwiftStarKit`, the pure-logic package)

1. **`ModelFamily`** — `.mellum` (and later `.lagunaXS`).
2. **`SamplerDefaults`** — `temperature`, `topK`, `topP`, `minP` (optional).
   `Variant.sampler` is optional; nil = engine family default. **Dead code this
   phase** (D6) — carried so the (b) contract is shaped, not wired.
3. **`RuntimeContract`** — the enforced per-variant contract:
   - `architecture: String` (`"mellum"`)
   - `rope: RopeContract` (`scalingType: String` = `"yarn"`,
     `freqBase: Double` = `500000.0`)
   - `quantLayout: QuantContract` (`downType: GGUFType` = `.q8_0`)
   - `memoryBudget: MemoryBudget` — **a function of context size**, not a
     constant: `totalBytes(at ctx: Int) -> Int64`. Weights (9.33 GiB) + scratch
     (~0.4 GiB) are constant; KV is linear in ctx, anchored at the documented
     (16k, 32k, 40k) → (0.26, 0.48, 0.59) GiB points. ctx outside [16k, 40k] is
     refused as *unsupported for the declared budget* (D4).
4. **`Variant`** — `id`, `displayName`, `modelFile: URL`, `family`,
   `sampler: SamplerDefaults?`, `contract: RuntimeContract`.
5. **`VariantRegistry`** — `static let all: [Variant]` + `resolve(id:)`.
   Hardcoded Swift; holds Mellum now, Laguna XS next week.
6. **`VariantResolver`** — the **single** source of `modelPath` resolution:
   `resolveModelFile(selectedVariantID:modelPath:envModel:fallback:) ->
   (url: URL, variant: Variant?)`. Both `EngineController.defaultSettings()` and
   `AgentController.defaultSettings()` call it, so the duplicated hardcoded
   Laguna default and the duplicated resolution logic each collapse to one place
   (C1/M4).
7. **`GGUFMetadataReader`** — parses GGUF v3. Reads the header to learn the kv
   and tensor-directory byte ranges, then seek-reads **those ranges** (no mmap,
   no fixed-prefix truncation — M5). Returns `GGUFMetadata`: `architecture:
   String?`, `ropeScalingType: String?`, `ropeFreqBase: Double?`, `tensorTypes:
   [String: GGUFType]`. A wrong GGUF version or a truncated directory is a named
   `.unreadable` parse failure, never a silent skip. A `static func` that owns
   its `FileHandle` transitively (M2).
8. **`VariantVerifier`** — pure function
   `verify(_ variant: Variant, metadata: GGUFMetadata) -> [VariantMismatch]`.
   No IO, no throws. Enforces exactly three facts:
   - architecture matches;
   - rope (`ropeScalingType` + `ropeFreqBase`) matches;
   - every `blk.N.ffn_down_exps.weight` tensor (N in 0..<28) is `.q8_0`.
   Iterates N explicitly; a **missing** key is a mismatch
   `.downQuant(layer: N, expected: .q8_0, actual: .missing)` — never a skip
   (I4). `.unreadableFile` is **not** in this return set (I3).
9. **`VariantGate`** — the single admission entry point:
   `admit(_ variant: Variant, availableBytes: Int64) -> VariantAdmission`,
   `VariantAdmission = .admitted | .contractMismatch([VariantMismatch]) |
   .infeasible(FeasibilityReason)`. Order: read metadata → verify → memory
   check. A reader failure is synthesized *here* as
   `.contractMismatch([.unreadableFile(path:reason:)])` (I3). `static func`,
   nonisolated, no mutable statics (M2).

All new types are `struct`/`enum` with explicit `Sendable` conformance; they
cross the `@MainActor` app boundary and the nonisolated `swiftstar-agenttest`
`main` (M2).

### Data flow

**Selection/launch (app).**
1. User picks "Mellum 2.1" in Settings (a `selectedVariantID` AppStorage +
   Picker over `VariantRegistry.all`, with a "Custom file…" entry preserving
   the raw-path escape hatch). Precedence (M1): `selectedVariantID` is nil or
   `"custom"` → legacy `modelPath`/`SWIFTSTAR_MODEL`/hardcoded fallback;
   otherwise `VariantRegistry.resolve(id)` → `variant.modelFile`, and the legacy
   `modelPath` is *ignored* (not overwritten), so a custom→Mellum→custom
   round-trip preserves the custom path.
2. `VariantResolver.resolveModelFile(...)` in both controllers returns the model
   file and the matching `Variant?`.
3. Each controller runs `VariantGate.admit(variant, availableBytes:)` *before*
   spawn **when a variant resolved** (C1: both controllers, not just
   `EngineController`). `.contractMismatch` → `state = .failed(.variantMismatch(message))`;
   `.infeasible` → the existing `.failed(.infeasible(message))` path. When no
   variant resolved (custom path), the gate is **skipped and the run is surfaced
   as unverified** (D7) — never silently passed as verified.

**Benchmark (harness).**
1. `swiftstar-agenttest --variant mellum-2.1 --spec roadmap` resolves the
   variant (falling back to `SWIFTSTAR_VARIANT` env) and runs `VariantGate.admit`
   **once, at the top of `main.swift`, before any `PoolOrchestrator`/
   `AgentSettings` construction** — so all three spawn sites (roadmap, fixture,
   repair) are covered (C1). It records `variant: <id>`, `model: <path>`,
   `samplerSource: "engine-family-default (undocumented)"`, and
   `availableBytesGiB` in `run-config.json` (I2/I7). `SWIFTSTAR_MODEL` remains
   the custom-path escape hatch (gated only if a variant resolves; otherwise
   recorded as `custom-unverified`).
2. The run grades competence (acceptance exit, tool calls, mutations) and
   performance (elapsed, generated tokens) exactly as today — no new throughput
   machinery.

### Error handling

- `VariantMismatch` is a typed, named enum: `.architecture(expected:actual:)`,
  `.rope(expected:actual:)`, `.downQuant(layer:expected:actual:)` (with
  `actual: .missing` for an absent tensor), and `.unreadableFile(path:reason:)`
  — the last synthesized by `VariantGate`, never by the verifier (I3). Each
  renders one human-actionable line.
- Refusals are loud and pre-spawn. `EngineFailure` gains
  `.variantMismatch(String)`. Like `.infeasible` today, the variant refusal is a
  **pre-spawn direct assignment** outside `Supervisor.transition` (the
  supervisor only governs post-spawn events) — acknowledged, consistent with
  the existing `.infeasible` pattern (M3).
- The verifier is pure and total; a wrong GGUF version or malformed file is a
  named `.unreadableFile` from the reader, never a crash and never a silent
  skip (I4/I6).

### Testing

- **`GGUFMetadataReader`**: parse a crafted sparse GGUF (the P12.2 generator
  approach — header + kv + tensor directory only) and assert every field; a v2
  magic → named `.unreadable`; a truncated tensor directory → named `.unreadable`,
  not a silent skip.
- **`VariantVerifier`**: crafted metadata with wrong architecture / wrong rope /
  wrong down-type → named mismatches; a metadata map **missing one layer** →
  `.downQuant(... actual: .missing)` (I4); correct Mellum metadata → empty.
- **`VariantGate`**: reader failure → `.contractMismatch([.unreadableFile])`;
  infeasible declared budget (e.g. 10.3 GiB at 40k vs 8 GiB available) →
  `.infeasible`; feasible → `.admitted`; contract mismatch takes precedence over
  the memory check.
- **`MemoryBudget.totalBytes(at:)`**: linear KV scaling reproduces ~10.2 GiB at
  32k and ~10.3 GiB at 40k; ctx outside [16k, 40k] refused.
- **`VariantRegistry`/`VariantResolver`**: `resolve("mellum-2.1")` returns the
  Mellum instance with the exact rope/quant/memory constants; resolution
  precedence (variant beats legacy path; custom round-trip preserves the path).
- **End-to-end benchmark**: `swiftstar-agenttest --variant mellum-2.1 --spec
  roadmap` against the real artifact — this is the acceptance gate itself.

## Decisions

- **D1** — `Variant`/`RuntimeContract`/`VariantRegistry` live in `SwiftStarKit`
  as pure value types; the registry is hardcoded Swift, not a resource file.
- **D2** — `GGUFMetadataReader` reads header + kv + tensor directory (seek-read
  their exact byte ranges); no weights are read or mmapped.
- **D3** — the verifier enforces exactly three facts (architecture, rope,
  down-type == Q8_0 on every layer); a missing tensor is a mismatch, not a skip.
  It does not re-implement the engine's full admission.
- **D4** — memory budget is a **function of context size** with documented
  provenance (9.33 GiB weights + ~0.4 GiB scratch + linear KV anchored at
  16k/32k/40k). ctx outside [16k, 40k] is refused for the Mellum variant as
  unsupported. For a preset variant, the gate uses the declared budget as the
  *floor*; if a persisted engine plan exists for the same variant + context
  size, the gate uses `max(declared, persisted)`. The persisted-plan +
  Laguna-correction path is unchanged for the raw/custom case.
- **D5** — `VariantGate.admit` is the single admission entry point for app and
  harness; verify-then-memory order; `.unreadableFile` is gate-synthesized.
- **D6** — sampler defaults are `optional` and **not wired to argv** this phase
  (Mellum's family default is undocumented). The capture records `samplerSource`
  so a future engine-default change is detectable. Wiring is a deferred one-liner.
- **D7** — the app gains `selectedVariantID` + a Picker; a shared
  `VariantResolver` resolves the model file for **both** controllers, each of
  which admits via `VariantGate` before spawn. Custom/raw paths are **declared
  unverified** and surfaced as such — never silently passed as verified.
- **D8** — `swiftstar-agenttest` gains `--variant <id>` / `SWIFTSTAR_VARIANT`;
  the gate runs **once at the top of `main.swift`** covering all spawn sites;
  `SWIFTSTAR_MODEL` remains the custom-path escape hatch; `run-config.json`
  records the variant, sampler source, and available bytes.
- **D9** — acceptance = the live-model basic-spec run. **Gated criterion:
  initiation** (≥1 tool call and ≥1 file written on `roadmap.md` — the
  historical failure was 0 tool calls, narration-only). **Performance is
  recorded, not gated, this phase** (no threshold; "fast enough" is trend data).
  **Failure policy:** if the live run shows no initiation, Mellum is **not**
  added to `VariantRegistry.all` as a shipped preset and P13-Mellum blocks on
  that result; a run that initiates (even if acceptance fails for
  harness-addressable reasons) ships the preset. No fixtures, no oracle, no
  target pass rate.

## Verification (done-when)

1. `VariantRegistry.resolve("mellum-2.1")` returns the Mellum instance with the
   rope/quant/memory constants above.
2. `VariantVerifier` unit tests pass: wrong architecture / rope / down-type and
   a missing layer are named refusals; correct Mellum metadata is clean.
3. `VariantGate.admit` refuses a reader failure, an infeasible budget, and a
   contract mismatch; admits a feasible Mellum variant. Both controllers and the
   harness go through it.
4. `MemoryBudget.totalBytes(at:)` reproduces the documented totals and refuses
   unsupported context sizes.
5. Selecting Mellum in Settings runs the verifier + memory gate before spawn in
   **both** the server and agent paths; a wrong file is refused by name, not by
   a late engine crash.
6. `swiftstar-agenttest --variant mellum-2.1 --spec roadmap` runs against the
   real artifact, records the variant + sampler source + available bytes in
   `run-config.json`, and shows initiation (tool calls + files written) on the
   basic spec — not the 0-call narration failure.
7. Build and full test suite green (`swift test`), with no new warnings under
   Swift 6 strict concurrency.

## Deferred (not this phase)

- **Steering profile** — a future `Variant` field telling the packet writer how
  broad/detailed to write and how much to micromanage. `RuntimeContract` and a
  future `SteeringProfile` stay separate structs; P13 only ensures the seam
  exists (a separate struct, not mixed into `RuntimeContract`).
- **Sampler-flag wiring** — pass `Variant.sampler` into `ServerCommand`/
  `AgentCommand` argv once Mellum's family defaults are known.
- **Mellum-shaped fixtures** and the **Q4_K oracle chain**.
- **Laguna XS 2.1** — one more `Variant` instance next week.
