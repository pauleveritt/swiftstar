# P3 verification record (2026-08-22)

Durable record for Phase P3 ("It can get its weights"). Executed on branch
`p3-it-can-get-its-weights` (worktree `.worktrees/p3-it-can-get-its-weights`),
spec-driven per `docs/sdd.md`.

## Test evidence

- **Fast tier** (`just test`): 60 tests in 10 suites, green in ~0.3s — Feasibility
  (known-good/known-broken/exact-fit/refusal-message), DownloadBitmap + ChunkedPlan
  (round-trip, width rejection, progress/missing math), BootLineParser (the real
  `ds4: memory:` line → planned bytes within a GiB of the P1 fixture's
  `planned_bytes`), plus all P2 tests.
- **Integration tier** (`just integration`): 63 tests in 11 suites green in ~3.3s —
  the P3 additions: `fullDownloadIsByteIdentical` (1 MB through the range server,
  byte-equal), `resumeDownloadsOnlyMissingChunks` (pre-seeded bitmap + part files
  for chunks 0–1; the server's range log proves only chunks 2–9 were fetched and the
  merged file is byte-equal), `serverErrorFailsCleanly` (wrong port → `.failed` with
  a message), plus all P2 integration tests.
- **App** (`just app`): bundle builds; launch smoke with a bogus `DS4_DIR` refuses to
  spawn the engine (engine-missing path) with no crash.
- **Download UI**: the Settings → Engine pane has a Download section (model picker,
  progress, cancel); the runner underneath is the integration-tested
  `DownloadRunner`. The literal button-click step is manual; its behavior is pinned
  by the integration tests.

## Shown-fail / break-and-restore records (binding rule 2)

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| Feasibility exact-fit (T1) | `>` → `>=` | `exactFitIsFeasible` failed | yes |
| Chunk plan missing-chunks (T2) | only even indices | `planProgressAndMissing` failed | yes |

## Real bugs found during P3 (by the tests/smoke, not by review)

1. **Range server**: died on SIGPIPE when a client closed early (HEAD) — fixed with
   `signal(SIGPIPE, SIG_IGN)` + proper HEAD handling (headers only, no body, no range
   log). Range parsing used the wrong header offset (served `0–end` instead of the
   requested slice) — rewritten to parse the value after `=`. The range log
   **overwrote** per request (`.atomic` write) — switched to append so the resume
   assertions can see every served range.
2. **Executable-target testability**: `@testable import SwiftStar` (an executable that
   imports SwiftUI) fails to link (`SwiftUICore.tbd` client restriction + missing
   symbols). Fixed by extracting the app-side testable logic into a `SwiftStarAppKit`
   library target (DownloadRunner, DownloadSpec, DownloadState, MemorySnapshot) —
   the same seam discipline the brief demands ("decisions live in Kit, app is thin").
   Documented plan deviation.

## Scope compliance

No multi-repo cataloguing (hardcoded target list), no torrent/P2P, no Downloads tab,
no engine-state resume. Feasibility covers RAM only (deficit + actionable levers);
the engine's own refusal still surfaces via the supervisor. No submodule bump.

## Feasibility gate behavior

`EngineController.startEngine` applies `Feasibility.check` before spawning when a
known plan exists (persisted from the engine's `ds4: memory:` boot line via
`BootLineParser`); an infeasible budget sets `.failed(.infeasible(message))` with a
computed, actionable message (deficit, available, and the close-apps/smaller-quant
levers). Unknown plans defer to the engine's own refusal. `MemorySnapshot.availableBytes`
= free + inactive pages (Activity Monitor's notion).

## Concept budget

**feasibility** is now defined (the engine's startup memory plan vs. available RAM,
computed, with an actionable refusal). **variant** remains a seed term (P12).
