# P22 — model switching live validation record

**Date:** 2026-08-28
**Phase:** P22 — More models: Laguna XS + model switching (model-switching arm)
**Status:** **live validation PASS** — one real switch, one refused switch, transcript preserved, provenance correct, pool re-spawned
**Spec:** [`2026-08-28-p22-model-switching-design.md`](../specs/2026-08-28-p22-model-switching-design.md)
**Implementation:** commits `6c6f1fe` (pure decision + tests), `d299fa8` (wiring), `c450e60` (toolbar action), `8d62c10` (GLM review fixes)

## What this document is

The evidence record for P22's model-switching forward item, produced by driving
the real app on the pinned engine (`external/ds4` @ `96286b3`,
`p20-dispatch-schema`) on the 128 GB M5 Max. Every claim below carries its
evidence path. The app was driven through its actual UI (toolbar model menu →
"Apply this model") via accessibility scripting; the wire/capture/provenance
records are the app's own artifacts, not probes.

## Method

- Launch: `.build/debug/SwiftStar` with `SWIFTSTAR_LOG=/tmp/p22-switch.log`
  (the controller's cross-spawn log: one `turn outcome:` line per finished
  turn, each carrying its model's file name).
- UI driving: AX (accessibility) — the toolbar model menu
  (`AXMenuButton` "cpu"), its items, and "Apply this model" were pressed
  through the accessibility API. The composer was focused + typed via
  synthetic key events (CGEvent).
- All app processes: one app process per phase (pids recorded below). Engine
  spawns are the app's own `ds4-agent` children.

## Evidence

### 1. Real switch: Laguna S → Laguna XS 2.1 (binding rules 3–5)

- App pid **65961 unchanged** across the switch (in-process stop → re-spawn,
  not an app relaunch).
- Pre-switch session: `captures/live/20260828-110319/` — provenance.md names
  `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`, ctx 51200, build `96286b3`.
- Two user turns held (via the composer): `Reply with only: pong` →
  `turn outcome: ... model=laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf ... tokens=3`;
  `What is 2+2? ...` → `... tokens=2` (SWIFTSTAR_LOG).
- Menu → "Laguna XS 2.1" → "Apply this model":
  - Old engine (pid 65963) stopped; new engine **pid 79054** spawned with:
    `-m .../laguna-xs-2.1-RoutedQ3_K-biased.gguf -c 32768 ... --ssd-streaming
    --ssd-streaming-cache-experts 3200 --prefill-chunk 4096 --subagent-pool 2`
    (process argv) — **XS model, context clamped 51200→32768 (spec D2), XS
    runtime flags carried, pool re-spawned (rule 5)**.
  - New session `captures/live/20260828-110803/provenance.md`: Model =
    `laguna-xs-2.1-RoutedQ3_K-biased.gguf`, Context: 32768 (rule 4).
  - **Transcript preserved (rule 3)**: the accessibility tree after the switch
    still showed both pre-switch user messages and their per-turn summaries
    (`AXStaticText val=Reply with only: pong`; `val=What is 2+2? ...`; the
    frozen summary rows `Decode 77 tok/s · ctx 1,400` / `Decode 118 tok/s ·
    ctx 1,424`).
  - One turn on XS: `Say hello in three words.` → `turn outcome: ...
    model=laguna-xs-2.1-RoutedQ3_K-biased.gguf ... tokens=5` (rule 4,
    per-turn). XS's own `ready` plan: `planned_bytes 7015923720` = 6.53 GiB —
    exactly the declared XS budget.

### 2. Second switch, accidental but real: XS → DeepSeek V4 Flash

While staging the refused-switch test, the DeepSeek selection was admitted and
spawned (the intended refusal lever was mathematically wrong — see §4). This
is recorded because it is genuine evidence:

- Menu → "DeepSeek V4 Flash" → "Apply this model": new engine **pid 79249**
  with `-m .../DeepSeek-...-fixed-0731.gguf -c 51200 ... --subagent-pool 2`;
  new session `captures/live/20260828-110927/provenance.md` names the
  DeepSeek file.
- **Live proof of the P25 Cycle 4b denominator through the app:** the gate
  admitted the 92.03 GiB DeepSeek load (`ready planned_bytes 98812439616`)
  under the Metal working-set ceiling (107.52 GiB). The pre-4b denominator
  (free+inactive pages, measured 82.71 GiB) would have **refused** this launch.
- One turn: `Reply with only: ok` → `turn outcome: ...
  model=DeepSeek-...-fixed-0731.gguf ... tokens=27`.
- Transcript again preserved: all three earlier turns still present in the AX
  tree after the DeepSeek spawn.

### 3. Refused switch — the session survives (binding rule 1)

- Relaunched the app (pid 82114) with `SWIFTSTAR_LAGUNA_XS_MODEL` pointing at
  the Mellum file (a legitimate harness override; the codebase's env-override
  seam — the same one `swiftstar-agenttest` uses). The default session came up
  on Laguna S (`captures/live/20260828-111200/`, provenance names the S file,
  wire `ready`).
- Menu → "Laguna XS 2.1" (which resolves to the Mellum file via the env) →
  "Apply this model":
  - **Engine pid unchanged (82112), capture dir unchanged (20260828-111200),
    status stayed `Ready`** — no stop, no re-spawn.
  - Transcript system row (AX value):
    `→ apply model refused: architecture mismatch: expected 'laguna', got
    'mellum'` + `down-quant mismatch on layer 1: expected q3_k, got q8_0`
    (+ the remaining sparse layers) — the readable refusal landed exactly as
    designed (spec D4: `.refused` → transcript system row, no `restartAgent`).

### 4. Why the intended infeasibility lever was wrong (honest note)

The refusal test originally targeted `VariantGate.admit`'s infeasible branch
(DeepSeek at a large context). Direct read of the memory model shows why that
cannot fire on this machine: `MemoryBudget.kvGiB` is anchored 16k→0.742,
32k→1.118, 40k→1.306 GiB and interpolates beyond 40k at that slope, so
DeepSeek needs **105.8 GiB at its maxContext 450,000 — under the 107.52 GiB
Metal ceiling** (the P25 design doc's own "~1.76 GiB headroom" note). No
registry variant is infeasible at any allowed context on 128 GB. The
contract-mismatch refusal (§3) exercises the same `.refused` wiring and
stop-refusal guarantee; the infeasible branch's message path is pinned by the
fast-tier tests (`refusedWithFeasibilityMessage`,
`noChangeWhenSameModelFileRegardlessOfAdmission`) and by
`VariantGate`'s own live refusal at fresh launch (P3-era evidence).

## Binding-rule checklist

| Rule | Evidence |
|---|---|
| 1. Admission before stop; never kill for an infeasible target | §3 — refusal, session untouched (pid/capture/status unchanged) |
| 2. Refuse mid-generation | Menu `.disabled(isGenerating)` (code) + pure rule pinned by `refusedWhileGeneratingEvenWhenAdmittedAndChanged` (test) |
| 3. Transcript preserved | §1, §2 — AX tree showed all prior turns after each switch |
| 4. Provenance per spawn = new model | §1, §2 — per-spawn provenance.md + per-turn `TurnOutcome.model` in SWIFTSTAR_LOG |
| 5. Pool re-spawns with the new model | §1 — `--subagent-pool 2` in the XS spawn argv |

## Fast tier

`swift test` — 741 tests, 106 suites, green (incl. 9 new
`ModelSwitchDecisionTests`). GLM 5.3 review: **approve with minor fixes**,
both folded (`8d62c10`).

## Files touched by the live run

Nothing in the repo was mutated by the run. Temp artifacts in `/tmp`:
`p22-switch.log`, `p22-app.out`, `ax`/`keytype` drivers. The app's
`UserDefaults` domain (`SwiftStar`) was reset to its pre-run state
(`selectedVariantID`/`contextSize` deleted).
