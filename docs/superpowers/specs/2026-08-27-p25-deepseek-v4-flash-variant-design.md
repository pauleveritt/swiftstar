# SwiftStar P25 — DeepSeek V4 Flash as a first-class variant

**Date:** 2026-08-27
**Status:** designed, not started — research extended and the ROADMAP P25 scoping
fork **resolved** (see "What this review overturned"). No Swift written.
**Phase:** P25 — More models, DeepSeek V4 Flash arm (the 128 GB rung of the
model ladder named in [`docs/laptop-ai.md:34`](../../laptop-ai.md), missing from
the app since P13 shipped the `Variant` machinery).

## Problem

`docs/laptop-ai.md` names DeepSeek V4 Flash "the flagship" at the 128 GB tier
and calls it **the reference the others are measured against**. All three lower
rungs shipped (Laguna S 64 GB, Laguna XS 32 GB, Mellum 16 GB). The reference
rung has never existed in SwiftStar: no `Variant`, no registry entry, no
`ModelFamily` case, and — until this review — no verified account of what
adding it would cost.

The ROADMAP P25 row ([`ROADMAP.md:226`](../../../ROADMAP.md)) recorded the
2026-08-27 research trail and deliberately left one decision open: **a faithful
port of ds4-control's Metal-allocator memory model, or a simpler linear
approximation first.** This document resolves that fork, and three others the
row did not know about.

## What this review overturned

The ROADMAP row's own framing was wrong in two places and incomplete in two
more. Each correction below is derived from a direct measurement or a direct
read, not from the predecessor's prose.

### 1. The faithful-vs-linear fork is a false dichotomy

The row treats "faithful Metal-allocator port" and "linear approximation" as a
trade of accuracy against effort. **They are the same answer.**

ds4-control's `Feasibility.swift` memory model is, for every context above the
4,096-token prefill cap, **affine in context**. Re-deriving each term:

| ds4 term | dependence on `ctx` |
|---|---|
| `rawBytes` | **constant** (`rawCap` saturates at 4,352 for ctx ≥ 4,224) |
| `ratio4Bytes` | linear (`21 × 1536 × (ctx/4 + 2)`) |
| `ratio128Bytes` | linear (`20 × 1024 × (ctx/128 + 2)`) |
| `scratchMatricesBytes` | linear (`2 × (ctx/4 + 2) × 4096 × 4`) |
| `attentionStageBytes` | **constant** (keyed on `prefillCap` only) |
| `metalSharedGraphWorkspaceBytes` | **constant** (keyed on `prefillCap` only) |
| `metalSessionGraphBytes` | **constant** (keyed on `prefillCap` only) |
| `metalIndexerScratchBytes` | linear + a sawtooth of period 4,096 (`ctx % prefillCap`) |

A least-squares line through the endpoints of `[16k, 1M]` fits the exact model
with a **worst-case residual of 30.5 MiB (0.37%)**, and that worst case is
entirely the indexer sawtooth.

SwiftStar's existing `MemoryBudget`
([`Variant.swift:154-211`](../../../Sources/SwiftStarKit/Variant.swift)) is
piecewise-linear over three anchors and *linearly extrapolates* above 40,960 —
which is exactly correct for an affine function. Laguna S already relies on
this (its `maxContext` of 150,000 is 14× beyond the top anchor). Feeding the
ds4 formulas' own outputs in as the three anchors reproduces the exact model
across the full range:

| ctx | ds4 exact (GiB) | SwiftStar 3-anchor (GiB) | delta |
|---:|---:|---:|---:|
| 16,384 | 95.8497 | 95.8497 | 0.0 MiB |
| 51,200 | 96.6319 | 96.6476 | +16.0 MiB (+0.016%) |
| 150,000 | 98.8924 | 98.9119 | +19.9 MiB (+0.020%) |
| 262,144 | 101.4820 | 101.4820 | 0.0 MiB |
| 524,288 | 107.4898 | 107.4898 | 0.0 MiB |
| 1,000,000 | 118.3877 | 118.3922 | +4.5 MiB (+0.004%) |

**Worst error across the whole 16k–1M range: 20 MiB, 0.02%, always on the
conservative side.** Against a 91 GiB model on a 128 GiB machine, that is
noise — three orders of magnitude below the decision margin.

**Resolution: neither branch of the fork as written.** Do the faithful
derivation **offline, once**, and ship the three constants it produces in the
existing `MemoryBudget` shape. Fidelity where it is checkable; simplicity where
it ships. `MemoryBudget` needs **no extension** — the row's claim that the shape
"need[s] real extension to hold it" is false.

### 2. `QuantContract` needs no extension either

The row flagged `QuantContract` alongside `MemoryBudget` as needing extension.
Read directly from the GGUF header of the real artifact (1,328 tensors, 62
metadata keys), the q2-q4-imatrix expert layout is:

- `blk.0..36.ffn_down_exps.weight` → **Q2_K** (37 layers)
- `blk.37..42.ffn_down_exps.weight` → **Q4_K** (6 layers)
- gate/up experts: IQ2_XXS on 0–36, Q4_K on 37–42 (not verified by the
  contract, which enforces the down projection only — same as every other
  variant)
- **no dense leading layer**: layer 0 is already MoE, unlike Laguna XS/S

That is a clean two-segment contract, structurally identical to the Laguna S
2.1 mixed layout the `segments:` initializer was built for
([`Variant.swift:129-134`](../../../Sources/SwiftStarKit/Variant.swift)):

```swift
QuantContract(
    segments: [
        QuantContract.Segment(downType: .q2_k, startLayer: 0, layerCount: 37),
        QuantContract.Segment(downType: .q4_k, startLayer: 37, layerCount: 43),
    ],
    downTensorPattern: "blk.%d.ffn_down_exps.weight"
)
```

`GGUFType` is a raw-value struct, not an exhaustive enum
([`GGUFMetadataReader.swift:6`](../../../Sources/SwiftStarKit/GGUFMetadataReader.swift)),
and both `.q2_k` and `.q4_k` are already declared. Nothing to add.

### 3. The real work is the admission denominator — and it is not DeepSeek-specific

This is the finding the ROADMAP row does not contain at all, and it is the only
genuine blocker.

`VariantGate.admit` compares the budget against `availableBytes`
([`VariantGate.swift:56`](../../../Sources/SwiftStarKit/VariantGate.swift)),
which the app supplies from `MemorySnapshot.availableBytes()` — **free +
inactive pages**
([`MemorySnapshot.swift:6-31`](../../../Sources/SwiftStarAppKit/MemorySnapshot.swift)).

Measured on this machine during this session:

```
free = 68.45 GiB   inactive = 14.25 GiB   ->  availableBytes = 82.71 GiB
DeepSeek V4 Flash q2-q4 minimum need (ctx 16,384) = 95.85 GiB
```

**The gate refuses the flagship on a machine that can genuinely run it**, and
whether it refuses depends on how much unrelated memory happened to be in use —
the same launch admits or refuses with the machine's weather. Free-plus-inactive
is the wrong question for a 91 GiB mmap'd, GPU-resident model: the binding
constraint is Metal's wired working set, not the free-page count.

ds4-control answered this with `recommendedMaxWorkingSetSize` plus the
`iogpu.wired_limit_mb` sysctl, and a distinct `wiredLimitTooLow(requiredMB:
advisoryMB:)` state carrying an actionable number
([`Feasibility.swift:11,36-71`](../../../../ds4-control/Sources/DS4Control/Model/Feasibility.swift)).
Measured here:

```
device: Apple M5 Max, 128.0 GiB unified
recommendedMaxWorkingSetSize = 115,448,725,504 B = 107.52 GiB
iogpu.wired_limit_mb = 0  (OS default; user has not raised it)
```

This change is **shared across every variant**, not part of the DeepSeek
variant. It is the highest-risk item in the phase and the one that most
deserves its own cycle.

### 4. Two small gaps the row missed, both cheap

- **`GGUFMetadataReader` hardcodes architecture-prefixed rope keys.** It has
  `mellum.rope.*` and `laguna.rope.*` cases and no generic prefix derivation
  ([`GGUFMetadataReader.swift:125-141`](../../../Sources/SwiftStarKit/GGUFMetadataReader.swift)).
  Without `deepseek4.rope.*` cases the reader returns nil for both rope fields
  and `VariantVerifier` refuses on a `.rope` mismatch. Exactly the gap the P13
  XS spec listed as "`laguna.rope.*` key support".
- **The weights are not on any search path.** `locateModel` searches the env
  override, `SWIFTSTAR_MODEL_DIR`, `~/models`, and `~/projects/ds4/gguf`
  ([`VariantRegistry.swift:26-42`](../../../Sources/SwiftStarKit/VariantRegistry.swift)).
  The DeepSeek artifacts are in neither of the two fixed directories (confirmed:
  `~/projects/ds4/gguf` holds only the Laguna line). Registering the variant
  without extending the paths fails
  `everyRegisteredVariantResolvesToAReadableFile`
  ([`VariantRegistryTests.swift:278`](../../../Tests/SwiftStarKitTests/VariantRegistryTests.swift))
  — which is precisely the failure mode `locateModel`'s own doc comment
  describes as how the XS default shipped broken.

### What is genuinely free

- **`ModelFamily` has zero switches outside its declaration.** Adding
  `.deepSeekV4Flash` ripples nowhere.
- **The picker is derived.** `ModelChoice.list(variants:)` maps
  `VariantRegistry.all` ([`ModelChoice.swift:22-26`](../../../Sources/SwiftStarKit/ModelChoice.swift)),
  so the menu row appears with no UI work.
- **No download.** Both copies are on disk, byte-identical at 97,591,747,456 B.
- **The default context needs no special-casing.** The app's 51,200 default
  ([`AgentDefaultSettings.swift:79`](../../../Sources/SwiftStarKit/AgentDefaultSettings.swift))
  falls inside the variant's supported range, unlike Mellum/XS whose
  `maxContext` sits below it and relies on `clampContext`.

## Gardenable facts (verified against the artifact + the pinned engine)

Read directly from
`~/Library/Application Support/DS4 Control/gguf/DeepSeek-V4-Flash-Layers37-42Q4KExperts-OtherExpertLayersIQ2XXSGateUp-Q2KDown-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-fixed-0731.gguf`
during this session.

- **Artifact:** GGUF v3, **1,328 tensors, 62 metadata keys**, 97,591,747,456
  bytes (90.8894 GiB). A byte-identical copy under the pre-`-0731` legacy name
  sits in `external/ds4/gguf/` (gitignored inside the submodule).
- **Architecture:** `general.architecture = "deepseek4"`.
- **Rope:** `deepseek4.rope.scaling.type = "yarn"`, `deepseek4.rope.freq_base =
  10000.0` (also `scaling.factor 16.0`, `original_context_length 65536`,
  `yarn_beta_fast 32.0`, `yarn_beta_slow 1.0`, `dimension_count 64`, and a
  separate `attention.compress_rope_freq_base = 160000.0`). The two
  contract-load-bearing values are **yarn / 10000.0** — note this differs from
  both Mellum and Laguna, which are yarn / 500000.0.
- **Shape:** `block_count 43`, `context_length 1048576`, `expert_count 256`,
  `expert_used_count 6`, `expert_shared_count 1`,
  `expert_feed_forward_length 2048`, `expert_gating_func 4`,
  `expert_weights_norm true`, `expert_weights_scale 1.5`.
- **Expert quant layout:** down projections Q2_K on layers 0–36, Q4_K on 37–42;
  gate/up IQ2_XXS on 0–36, Q4_K on 37–42. Expert tensor dims
  `[4096, 2048, 256]` (gate/up) and `[2048, 4096, 256]` (down).
- **Engine support is real, not merely in source.** `strings` on the **compiled**
  `external/ds4/ds4-agent` (pin `f56d0ca`, 2026-08-25) shows the `deepseek4.*`
  metadata key family and a DeepSeek4-specific layer-layout error string. The
  pin postdates every DeepSeek-related upstream commit found (latest 2026-08-16).
- **Derived memory budget** (the three constants Cycle 3 ships, from ds4's own
  formulas at the three anchors, decomposed into SwiftStar's fields):

  ```
  weightsGiB  = 90.8894      (exact GGUF bytes)
  scratchGiB  =  4.2179      (shared graph 4.1973 + session graph 0.0206;
                              context-independent above the 4,096 prefill cap)
  kvGiBAt16k  =  0.742351    (metalContextBytes + metalIndexerScratchBytes)
  kvGiBAt32k  =  1.117839
  kvGiBAt40k  =  1.305583
  ```

- **Operating envelope on this machine (M5 Max, 128 GiB):**
  - Under the **OS-default** Metal working set (107.52 GiB), the flagship is
    resident-feasible up to **ctx 526,267**. No sysctl, no sudo, no user action.
  - The full **1M** window needs 118.39 GiB — above the default, below the
    RAM-minus-4-GiB advisory (124 GiB). It requires raising
    `iogpu.wired_limit_mb`, which is exactly the advisory refusal ds4-control
    shipped.
  - **Think Max is reachable**: ds4's `DS4_THINK_MAX_MIN_CONTEXT` is 393,216 and
    needs ≥128 GiB RAM; at that context the working set is 104.49 GiB — inside
    the default limit. The flagship can think at full depth on this box without
    touching a sysctl.
- **Open upstream caveat, non-blocking:**
  [`antirez/ds4#635`](https://github.com/antirez/ds4/issues/635) reports an
  SSD-streaming long-context correctness regression **on ROCm/Strix Halo**,
  not reproduced on Metal, not seen in resident mode. Irrelevant to a resident
  launch; re-check only if SSD streaming is ever enabled for this variant.

## Scope

**In:** `deepseek4.rope.*` keys in `GGUFMetadataReader`; two additional
`locateModel` search directories; `ModelFamily.deepSeekV4Flash`; the
`deepseek-v4-flash` preset in `VariantRegistry` (two-segment `QuantContract`,
derived `MemoryBudget`); an offline oracle test pinning the budget against a
test-side port of ds4's four Metal formulas; making the admission denominator
injectable and switching it to a Metal working-set-aware limit with an
actionable advisory; unit tests throughout; a live acceptance run.

**Out:** **SSD streaming.** `docs/laptop-ai.md` places the flagship at the
128 GB tier as *resident* — streaming is the 32 GB Laguna XS story. It is also
100% unbuilt in SwiftStar (only the three argv flags exist, and the engine owns
the logic), and ds4-control's design for it is a separate large scope
(`~/projects/ds4-control/docs/superpowers/specs/2026-08-12-ssd-streaming-design.md`).
Also out: the V4 Pro sibling (61 layers, ≥512 GiB — not a laptop model); the
other two Flash quants (q2 at 81 GiB, q4 at 153 GiB) — one variant, one quant,
the one `laptop-ai.md` means; a Settings download row (weights are local); the
sampler-flag wiring (still deferred project-wide since Mellum).

## Feature cycles

Six cycles, each with a verification gate that fails loudly and independently.
The ordering is chosen so that **the two highest-value cycles (1–3) are pure,
offline, and deterministic** — safe to run unattended — and the one genuinely
risky change is isolated and split.

### Cycle 1 — The file is findable and its metadata parses

**Change:** add `deepseek4.rope.scaling.type` / `deepseek4.rope.freq_base` cases
to `GGUFMetadataReader`; add the two DeepSeek directories to `locateModel`.
**Gate:** a new test parses the real artifact and asserts
`architecture == "deepseek4"`, `ropeScalingType == "yarn"`,
`ropeFreqBase == 10000.0`; existing reader tests stay green;
`everyRegisteredVariantResolvesToAReadableFile` stays green.
**Why alone:** the only edit to a parser three shipped variants depend on.
Isolating it means a regression here can never be mistaken for a variant bug.
**Risk:** very low — purely additive, and no variant is registered yet, so
there is no user-visible change at all.

### Cycle 2 — The contract verifies against the real file

**Change:** `ModelFamily.deepSeekV4Flash`; the `deepseek-v4-flash` registry
entry with architecture, rope, and the two-segment `QuantContract`. Ship a
*provisional* `MemoryBudget` (the Cycle 3 constants are fine as a placeholder;
they are simply not yet pinned by a test).
**Gate:** `VariantVerifier.verify(...)` returns **zero mismatches** against the
real 1,328-tensor file — this checks all 43 down-projection tensors by name and
type, so a single wrong segment boundary fails it. Registry tests green. The
picker row appears for free.
**Risk:** low. Known intermediate state — see "Intermediate states" below.

### Cycle 3 — The budget is right, and provably so

**Change:** replace the provisional constants with the derived ones; add an
oracle test that ports ds4's four Metal formulas (`metalContextBytes`,
`metalSharedGraphWorkspaceBytes`, `metalSessionGraphBytes`,
`metalIndexerScratchBytes`) as **test-side reference code** and asserts the
shipped three-constant budget agrees across a context sweep.
**Gate:** the oracle test, tolerance 25 MiB (measured worst case: 20 MiB).
**Why this shape:** this is where "faithful" actually happens — the exact
allocator math is written down and checkable — while the shipped code stays
three numbers in the same shape as every other variant. If a future engine pin
changes the allocator, this test fails and names the drift, which is precisely
the "re-fetch, never carry forward" discipline
[`docs/harvest/ds4-control.md:27-31`](../../../docs/harvest/ds4-control.md)
demands of every numeric fact.
**Risk:** low-to-medium and *self-announcing* — a mis-ported formula makes the
test disagree with the constants, so being wrong is loud rather than silent.
Fully offline and deterministic: the best unattended work in the phase.

### Cycle 4a — Make the admission denominator injectable (no behavior change)

**Change:** thread the available-bytes source through the admission path as an
injected value/closure, defaulting to today's `MemorySnapshot.availableBytes()`.
**Gate:** every existing `VariantGate` test passes **unchanged**; a new test
proves injection works by feeding a fixed value.
**Why alone:** a pure refactor with a provable no-op property is a categorically
different risk from a semantics change. Splitting means the semantics change
lands as a small, readable diff.
**Risk:** low. Safe unattended.

### Cycle 4b — Ask the right question

**Change:** default the denominator to a Metal working-set-aware limit
(`recommendedMaxWorkingSetSize`, overridden by `iogpu.wired_limit_mb` when
raised), and add the actionable "raise your wired limit to N MB" refusal
alongside the existing deficit message.
**Gate:** with an injected limit, table-driven tests over both regimes; on this
machine the flagship admits at ctx ≤ ~526k and refuses above it with the
advisory number. Mellum/XS/S admission outcomes must be re-confirmed — they get
a *more* permissive denominator (107.52 vs. today's weather-dependent value), so
the check is that nothing that should refuse now admits.
**Risk:** **highest in the phase.** Shared code path, changes behavior for every
variant, and the failure mode of being too permissive is a machine hang rather
than a test failure. **Recommend supervision.** If run unattended, constrain it
to injected limits only and leave the default switch as a separate reviewed
commit.

### Cycle 5 — It actually runs

**Change:** none (verification only).
**Gate:** a live headless launch at a chosen context; compare the engine's
reported resident bytes on the `ready` event against the declared budget;
one agentclinic eval, matching the P22 XS acceptance pattern
([`2026-08-27-p22-laguna-xs-acceptance-verdict.md`](../../research/2026-08-27-p22-laguna-xs-acceptance-verdict.md)).
**Why it cannot be skipped:** every number above is derived from formulas and
file headers. The predecessor ran this model, but *SwiftStar* never has —
"merged ≠ verified-merged", the same caveat the XS spec raised. This is also
where P24's guardrail applies: a predicted footprint is a claim, and the paired
measurement is the bill.
**Risk:** needs the machine and a human. A 91 GiB resident launch is not
unattended work.

### Cycle 6 — SSD streaming (deferred, not scheduled)

Left out deliberately; re-open only with a reason, and re-check
[`antirez/ds4#635`](https://github.com/antirez/ds4/issues/635) first.

### Intermediate states this creates

Between Cycle 2 and Cycle 4b the variant is **selectable but may refuse** —
admission depends on free-plus-inactive pages, so the same launch succeeds or
fails with the machine's memory weather. Two options:

1. **Accept it.** The refusal is accurate and actionable, and the window is two
   cycles wide. Recommended.
2. Gate registration behind an env flag until 4b lands.

Not recommended: reordering 4b earlier. It is the riskiest change and benefits
from landing *after* there is a concrete second consumer proving it matters.

## Notes for an unattended run

- **Cycles 1–3 and 4a are safe unattended.** They are offline, deterministic,
  and each has a gate that fails loudly. Cycle 3 is the highest-value one.
- **Cycle 4b wants review**; Cycle 5 requires a human.
- **Do not "fix" a failing oracle test by loosening its tolerance.** If Cycle 3
  disagrees by more than ~25 MiB, the formula port is wrong — that is the test
  doing its job. Re-derive; do not widen.
- **Do not delete either GGUF copy.** Disk shows ~206 GiB available against two
  91 GiB copies; freeing the legacy duplicate in `external/ds4/gguf/` is
  tempting and is the user's call, not the implementation's.
- **Every numeric fact here is re-checkable** and should be re-checked rather
  than trusted if the `external/ds4` pin moves — the preview-weights caveat in
  [`docs/harvest/ds4-control.md:27-31`](../../../docs/harvest/ds4-control.md)
  applies in full.

## Open questions

1. **What `maxContext` does the variant declare?** Candidates: 524,288 (a round
   number just inside the OS-default Metal limit of ctx 526,267), or 1,000,000
   (the true ceiling, relying on Cycle 4b's advisory to refuse the top of the
   range with an actionable message). The second is more honest about the
   model's capability; the first never asks the user for a sysctl. Leaning
   **524,288** for the first landing, with 1M reachable once 4b's advisory is
   proven in practice.
2. **Which artifact path wins?** The `-0731` copy under `~/Library/Application
   Support/DS4 Control/gguf/` is the current published name and matches the
   upstream SHA-256; the `external/ds4/gguf/` copy carries the legacy name.
   Prefer the `-0731` path, and treat the legacy copy as a fallback only.
3. **Does Cycle 4b change any shipped variant's behavior in practice?** Expected
   answer is "yes, all three become *more* likely to admit" — which is correct,
   but should be stated and measured rather than assumed.
