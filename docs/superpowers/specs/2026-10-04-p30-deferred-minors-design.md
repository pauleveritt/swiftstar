# SwiftStar P30 design: P29.10's deferred minors

**Date:** 2026-10-04  
**Status:** design, approved in chat by the owner (2026-10-04)  
**Phase:** P — cycle P30 (phase P's last cycles; closes at P32)

## Goal

Close the four loose ends P29.10 (the toolbar menus) left in the Backlog, all
of them in Kit/AppKit code against the fake engine — none need a live
`ds4-dogfood` session, since something else has the GPU right now.

## Decisions

1. **Mid-turn restart gets a test, not a behavior change.** `restartIfRunning()`
   (`EngineController.swift:122-125`) fires whenever `model.phase == .running`,
   which includes mid-generation; `canChoose` (line 90-92) only blocks
   `.starting`/`.quitting`. This is by design — the menu choice is its own
   confirmation — but it was shipped with no automated test. All three
   selectors (`select(workspace:)`, `select(modelID:)`, `select(contextSize:)`)
   share `restartIfRunning()`, so one integration test (pick a model while a
   turn is running; assert the turn ends and a new session starts with the new
   setting) covers the shared path.
2. **The catalog cache keys on path + modification date, not path alone.**
   `loadCatalogIfNeeded()` (`EngineController.swift:141-144`) currently keys
   solely on `catalogExecutable == path`, so an engine upgraded in place (same
   path, new binary — exactly what `uv tool install --force` does) keeps
   serving the stale list until the app relaunches. Fix: track the resolved
   path's modification date alongside the path; a changed mtime invalidates
   the cache the same as a changed path. Owner decision: fix, not just test
   (2026-10-04).
3. **The loader reaps on timeout.** `EngineModelCatalogLoader.run`'s timeout
   branch (`EngineModelCatalogLoader.swift:80-84`) returns `.timedOut` without
   closing `errHandle` or calling `process.waitUntilExit()`. Fix: close both
   pipe handles and wait for the process (the scheduled `killer` has already
   fired or is about to) before returning, so the child is reaped and no
   reader thread is left blocked past the kill grace.
4. **The stderr tail reads the tail.** Line 91 takes
   `errBox.value.prefix(4096)` when the comment and the caller both want the
   *last* line of stderr. Fix: `.suffix(4096)`, so verbose stderr doesn't push
   the real last line out of the window.

## Out of scope

The loader's SIGKILL pid-reuse window (`EngineModelCatalogLoader.swift:60`):
`kill(pid, SIGKILL)` after an `isRunning` check has a TOCTOU gap, but it's
already minimal (microseconds, inside a 1-second-after-timeout grace) and
Foundation's `Process` has no safer force-kill primitive. Left as a documented,
accepted risk rather than reworked here.

## Testing

- Fast tier: a unit test for the path+mtime cache-invalidation decision
  (`loadCatalogIfNeeded` refetches when the resolved file's mtime changes,
  even with the same path).
- Integration tier (fake engine): the mid-turn restart test; a loader test
  that a timed-out child is reaped (process no longer running, no hang) using
  `FAKE_ENGINE_MODELS_SLEEP_MS` past the loader's timeout; a loader test that
  a stderr blob over 4 KiB still reports its true last line.

## Success criteria

1. Picking a model while a turn is running ends the turn and the next session
   reflects the new model — reproducible in the integration tier.
2. Upgrading the fake engine's mtime at the same path (no path change)
   triggers a refetch on the next `loadCatalogIfNeeded()`.
3. A loader timeout leaves no running child and no blocked reader thread.
4. A stderr blob over 4 KiB resolves to its actual last line, not a line from
   within the first 4 KiB.
