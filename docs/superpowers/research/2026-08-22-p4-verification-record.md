# P4 verification record (2026-08-22)

Durable record for Phase P4 ("It shows what the machine is doing"). Executed on
branch `p4-it-shows-what-the-machine-is-doing` (worktree
`.worktrees/p4-it-shows-what-the-machine-is-doing`), spec-driven per `docs/sdd.md`.
Spec: `docs/superpowers/specs/2026-08-22-p4-it-shows-what-the-machine-is-doing-design.md`.

## Test evidence

- **Fast tier** (`just test`): 78 tests green; 10 integration tests skipped by
  the env gate — no model, no network, no subprocess (tripwire-guarded). New
  suites: `WireEventParserTests` (7), `MetricsReducerTests` (4), `DialLogicTests`
  (5).
- **Integration tier** (`just integration`): 88 tests green across 16 suites —
  the 78 fast tests plus the 10 env-gated. P4 additions:
  `ProcessStatsCollectorTests` (2 — collector returns a finite, sanitized
  snapshot for a real `/bin/sleep` pid; nil pid → nil resident) and
  `FixtureReplayTests` (2 — bundled fixture byte-identical to
  `fixtures/agent/golden.ndjson`; replay yields `status` + `ready` through the
  reducer with the expected budget).
- **App bundle** (`just app`): `.build/SwiftStar.app` builds; the Metrics tab
  replaces the placeholder. The interactive GUI smoke (tab renders the replayed
  context/throughput dials and live memory/GPU/CPU/power) is a manual step, as
  in P2/P3 — the deterministic behavior is pinned by the tiers above.

## Shown-fail / break-and-restore records (binding rule 2)

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| status line parses (T1) | `case "status"` → `.ignored` | `statusLineParsesSnapshot` and `goldenNdjsonParsesWithoutRefusing` failed | yes |
| rate ratchet (T2) | unconditional `prefillTPS` assignment | `ratchetHoldsLastNonZeroRates` failed | yes |
| context threshold (T3) | warning threshold = critical threshold | `contextThresholdsAreAbsolute` failed (37,500 and 74,999 read healthy) | yes |
| footprint from pid (T4) | `residentBytes` returns nil unconditionally | `collectReturnsSanitizedSnapshot` failed (resident nil) | yes |
| replay yields lines (T5) | `continue` drops every line | `replayYieldsStatusAndReadyThroughReducer` failed | yes |

## Real bugs / findings during P4 (by build/tests, not by review)

1. **IOReport is not linkable by default.** `@_silgen_name` declares the private
   IOReport symbols, but the linker cannot resolve them without
   `.linkedLibrary("IOReport")` on `SwiftStarAppKit` (the lib lives in the dyld
   shared cache). Found by the Task 4 build; fixed in `Package.swift`, cited from
   `ds4-control`'s `Package.swift` (facts cross, code does not). This is the one
   discovery the plan's risk flag anticipated.
2. **`ProcessStatsCollector` must be `public`.** `MetricsModel` (in the SwiftStar
   target) could not see the internal actor; made `public` with a `public init`.

## GLM 5.2 review (applied at planning time)

Spec and plan were reviewed by GLM 5.2 (two rounds, OpenRouter `z-ai/glm-5.2`)
before execution; the accepted findings are recorded in the plan's Self-Review
section (commit `8748d82`): actor isolation + async IOReport sampling (no
main-actor block), the GPU-iterator release fix, the Task 4 shown-fail,
saturating CPU deltas, the replay cadence parameter, and the badge→banner
wording. The IOReport linker flag was not caught by that review — it was found
by the build.

## GLM 5.2 implementation review (applied post-implementation)

The committed implementation was reviewed by GLM 5.2 (OpenRouter `z-ai/glm-5.2`)
and the accepted findings applied:

1. **IOReport subscription was re-created every sample (leak).** The first
   `IOReportPower.totalWatts()` created a fresh subscription + channel set on
   every call (once/second) and never released the `subscribed` output — a
   continuous leak. Fixed by restructuring `IOReportPower` into a class that
   subscribes once in `init` and reuses the cached handles, releasing the
   `subscribed` output immediately (mirroring `ds4-control`'s working
   `IOReportBridge`).
2. **`stop()` did not nil out its tasks**, so `start()` could not restart after
   a stop. Fixed by clearing `collectTask`/`replayTask` in `stop()`.
3. **GPU utilization had no upper clamp** (CPU already clamped to 100); added
   `min(100.0, …)` for consistency.

Dismissed after verification: "use `subscribed` not `chanPtr` for samples" (the
working predecessor uses the original channels and releases `subscribed`
immediately), "fixture not bundled" (the byte-equality integration test proves
the bundle contains `golden.ndjson`), and "test counts are vacuous" (the
`> 0` invariants deliberately match the P2 SSEParser test's "real invariants,
not counts" stance, so a recapture does not break them).

## Concept budget

No new terms. **fixture** already covers the replay source; "replay" earns no
term of its own (a mechanism, not a design concept).

## Scope compliance

No state dial, no throttle-% readout, no diagnostics (P6), no live `ds4-agent`
spawn, no fork/submodule change, no live-tier capture — P4 needed no weights.
