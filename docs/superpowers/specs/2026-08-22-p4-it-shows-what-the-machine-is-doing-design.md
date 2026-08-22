# SwiftStar P4 design: it shows what the machine is doing

**Date:** 2026-08-22
**Status:** approved by delegation ("finish this spec and plan on your own; go with
your recommendations"). The phase list and architecture are settled by `BRIEF.md` /
`ROADMAP.md` / `2026-08-21-swiftstar-design.md`; the data-source finding that frames
P4 is `docs/superpowers/research/2026-08-22-p4-sequencing-findings.md`.
**Phase:** P4 — It shows what the machine is doing.

This spec is the authority on *how* P4 is done. It does not reopen the phase list, the
architecture, or the engine seam.

## Problem

P3 left the app able to get its weights and refuse an infeasible launch — but with no
way to *see* what the engine and the machine are doing while a session runs. The
telemetry harvest (`docs/harvest/telemetry-findings.md`) is the single most important
input to this app: per-turn prefill throughput degrades ~7× as accumulated context
grows (≈300–360 tok/s at ~3,400 `ctx_used` vs ≈41–46 tok/s at ~92,500), and it is
compute-bound (98% GPU) rather than overhead. P4 ships the surface that makes that
curve *visible*: a Metrics tab led by absolute `ctx_used` and prefill throughput, with
memory, GPU, CPU, and power alongside — on fixed-width, jitter-proof readouts.

Two data sources feed the tab, and they are deliberately not conflated:

- **Wire-carried telemetry** — `ctx_used`, `ctx_size`, `prefill_tps`, `gen_tps` — lives
  only on the `ds4-agent --json-events` `status` event (fork-ledger divergence #4).
  The app drives `ds4-server` for chat (its SSE carries none of this), and `ds4-agent`
  is P7. So these lead dials are **fixture-driven** in P4: replayed from the committed
  `fixtures/agent/golden.ndjson` (1053 `status` events, 7 `ready` events), clearly
  badged, until P7's agent migration lights them live.
- **OS-level telemetry** — memory footprint, GPU%, CPU%, watts — is collected from the
  running `ds4-server` process and the hardware, *not* from the wire. It is **live
  today**, independent of the agent-wire problem.

The machine dials are live; the lead dials are replayed until P7. P4 must **not** spawn
`ds4-agent` live (its safety surface — workspace grant, shell toggle — is P7, and two
~48 GiB model loads are infeasible).

## Gardenable facts (with citations)

- **Wire shape** (`external/ds4/docs/json-events.md`): every stdout line is a JSON
  object with a `t` field. `status` carries `state`, `prefill_done`, `prefill_total`,
  `prefill_tps`, `generated`, `gen_tps`, `ctx_used`, `ctx_size`, `power`, `error`,
  throttled ≤200 ms with exact-repeat dedup. `ready` carries `kv_bytes`,
  `scratch_bytes`, `model_bytes`, `planned_bytes` — all four absent when the engine has
  no plan (`ctx_size <= 0`). `prefill_tps` and `gen_tps` are never both non-zero — a
  readout must ratchet each one's last non-zero value.
- **Fixture** (`fixtures/agent/golden.ndjson`, P1): verbatim `ds4-agent --json-events`
  capture; 1053 `status` + 7 `ready` events. Its `ready.planned_bytes` = 49,943,965,040
  (46.51 GiB), identical to the `ds4: memory:` boot line (the provenance doc's
  memory-budget verification table).
- **The five widget learnings** (`docs/harvest/telemetry-findings.md`): (1) anchor
  context on **absolute** `ctx_used`, not a fraction of `ctx_size` (a percentage fires
  late on a big window, early on a small one); (2) a live numeric readout jitters
  unless **fixed-width** — numbers get a fixed-width field, only the trailing message
  moves; (3) the rate ratchet is a **wire fact** and belongs in the parser's model, not
  the view; (4) a stroked ring's hit region must widen to its frame or its tooltip is
  unreachable; (5) memory and context want **different thresholds** — memory keeps
  generic severity thresholds, context keeps curve-shaped ones. "Prompt" and "Decode"
  are the user-facing words for prefill and generation.
- **Threshold anchors** (`telemetry-findings.md`): the ~7× degradation was measured at
  ~92,500 `ctx_used` on a 150,000 everyday window; the prototype's curve-shaped
  thresholds were warning at 25% and critical at 50% of the window (deliberately not
  the generic 70/90). Re-anchored to absolute tokens that is warning ≈ 37,500, critical
  ≈ 75,000 — provisional, and the harvest's rule applies: *re-anchor before trusting
  anywhere else*.
- **Collector facts** (all cite `~/projects/ds4-control`; code does not cross, facts
  cross with a citation and a fresh test):
  - Per-process footprint: `proc_pid_rusage(pid, RUSAGE_INFO_V4, …)` → `ri_phys_footprint`
    (bytes), verified against `ps` by the predecessor.
  - CPU%: `host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, …)`, tick
    delta across `CPU_STATE_MAX` entries.
  - GPU%: `IOServiceMatching("IOAccelerator")` → `IORegistryEntryCreateCFProperties`
    → `PerformanceStatistics` → `"GPU Activity(%)"` (fallbacks `"Device Utilization %"`,
    `"gpuActivity"`).
  - Power: private `IOReport` FFI (`IOReportCopyChannelsInGroup` et al., approach from
    vladkens/macmon, MIT) on group `"Energy Model"`; channels `"GPU Energy"`,
    `*"CPU Energy"` (suffix), `"ANE"` (prefix); units `mJ`/`uJ`/`nJ` → watts =
    energy / elapsed / (1e3 for mJ). Idle draw is under 1 W.

## Decisions

### D1 — Wire model in Kit, mirroring `SSEParser`

`WireEventParser` (Kit, pure) is a line-in/event-out streaming consumer shaped like
`SSEParser`: `feed(_ line: String) -> WireEvent?`. `WireEvent` is `.status(StatusSnapshot)`,
`.ready(plannedBytes: Int64?)`, `.ignored(String)`. `StatusSnapshot` carries `ctxUsed:
Int`, `ctxSize: Int`, `prefillTPS: Double`, `genTPS: Double`. Anything not modelled
(`text`, `think`, `tool`, `queued`, malformed JSON, unknown `t`) is `.ignored`, never
refused — binding rule 7 (no handshake before P5) and the forward-compatible fallback.
Blank lines return nil. The `status` `power` (throttle %) and `error` fields are
deliberately not extracted (throttle is Settings-adjacent, errors are the supervisor's
job).

### D2 — The ratchet lives in `MetricsReducer`, not the view

`MetricsReducer` folds `WireEvent` into `MetricsState` (both Kit, pure). `MetricsState`
holds `ctxUsed: Int?`, `ctxSize: Int?`, `prefillTPS: Double`, `genTPS: Double`,
`memoryBudgetPlannedBytes: Int64?`. The reducer ratchets: a zero `prefillTPS`/`genTPS`
leaves the previous non-zero value in place (the wire fact). `.ready` updates
`memoryBudgetPlannedBytes`. `.ignored` is a no-op. This is the "wire fact belongs in the
model" learning.

### D3 — `DialLogic`: the learnings as pure functions

`DialLogic` (Kit, pure) exposes:

- `Severity` (`.healthy`, `.warning`, `.critical`).
- `contextSeverity(ctxUsed: Int) -> Severity` — absolute-anchored, curve-shaped:
  `< 37_500` healthy, `< 75_000` warning, else critical. Constants are named and
  documented as provisional (re-anchor rule).
- `memorySeverity(residentBytes: Int64, plannedBytes: Int64) -> Severity` — generic:
  `≥ 0.90` critical, `≥ 0.70` warning, else healthy; `plannedBytes <= 0` → healthy.
- `fixedWidth(_ text: String, width: Int) -> String` — left-pads to a fixed width, so
  value changes don't move the surrounding line (learning #2).
- `sanitize(_ raw: MachineSnapshot) -> MachineSnapshot` — clamps negatives to 0 and
  NaN to 0 (private-API hardware reads can return garbage; the surface never shows it).

Color is a view concern: `Severity` maps to a color in `MetricsView`, never in Kit.

### D4 — Live machine collectors in AppKit, sanitization in Kit

`ProcessStatsCollector` (SwiftStarAppKit) produces `MachineSnapshot` (Kit struct:
`residentBytes: Int64?`, `watts: Double`, `gpuUtilization: Double`, `cpuUtilization:
Double`) from the four sources in the gardenable facts. `residentBytes` is nil when no
pid is supplied (per-process); watts/GPU/CPU are system-wide and always collected. The
collector returns `DialLogic.sanitize(...)` output — raw reads are never surfaced. The
IOReport piece is the one discovery-driven risk: the FFI and channel keys are cited
facts (macmon/ds4-control), implemented fresh here.

### D5 — Fixture replay drives the lead dials

`FixtureReplay` (SwiftStarAppKit) bundles `fixtures/agent/golden.ndjson` as an app
resource and feeds its lines through `WireEventParser` on a fixed cadence, so the lead
dials have data before P7. The bundled copy is guarded against drift by an integration
test asserting it is byte-identical to the repo fixture. The replay is single-pass
(then the ratcheted values hold) — no looping, no fabricated continuity.

### D6 — App surface: MetricsModel + MetricsView

`MetricsModel` (SwiftStar, `@Observable`) holds `MetricsState`, `MachineSnapshot`, and
`isReplayingWire: Bool`. It drives the collector on a timer and the replay task; it
takes the engine pid from `EngineController` (already owns the `ds4-server` `Process`).
`MetricsView` replaces the Metrics placeholder with the six dials, rendered through
`DialLogic`, with:

- a **"capture replay" badge** on the context and throughput dials whenever
  `isReplayingWire` is true — recorded numbers are never presented as live (the machine
  dials are never badged);
- the memory dial comparing live footprint against the **live** planned budget
  (`lastKnownPlannedBytes` from the P3 boot-line parser when known, else
  `memoryBudgetPlannedBytes`) — a replayed budget must not be paired with a live
  footprint on a different machine;
- the stroked context ring with its hit region widened to the frame (learning #4).

### D7 — Scope discipline

P4 does **not** ship: a state/phase dial, the throttle-% readout, diagnostics or the
deterministic analyzer (P6), sparklines or history, a live `ds4-agent` spawn, any fork
or submodule change, or any live-tier capture (P4 needs no weights — the fixture is
committed and the collectors read the OS). The tab is the surface; interpretation is
P6.

## Done when

1. **Fast tier** (`just test`): the parser handles `status` → correct snapshot values,
   `ready` → `plannedBytes`, `text`/`think`/`tool`/`queued`/malformed → `.ignored`,
   blank → nil (pinned against `golden.ndjson` and inline lines); the reducer ratchets
   (a zero rate holds the last non-zero); `contextSeverity`, `memorySeverity`,
   `fixedWidth`, and `sanitize` are pinned. Every new test shown to fail first.
2. **Integration tier** (`just integration`): the collector returns a finite,
   non-negative, sanitized `MachineSnapshot` for a real spawned process (footprint
   plausible, utilizations in 0–100); the bundled fixture is byte-identical to
   `fixtures/agent/golden.ndjson`; replay yields the expected snapshots.
3. **App smoke** (manual): the Metrics tab shows live memory/GPU/CPU/power for the
   running `ds4-server` and a badged replay for context/throughput; no weights, no
   network, no second process.
4. **ROADMAP** marks P4 complete; concept budget reviewed (no new terms needed —
   "fixture" already covers replay).
