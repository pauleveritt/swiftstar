---
phase: P24
cycle: P24.2-read-guard-redecision
lifecycle: closed
---

# P24.2 Read-Guard Re-decision Implementation Plan

## Goal

Use a post-windowing measurement to decide whether the read-guard and pool
`readCache` should return, then make the pool instrument match the product.

## Work completed

### 1. Retire the pool cache if the guard does not return

Update the pool-read tests and remove the whole-file/hash-cache branch from
`Sources/SwiftStarAppKit/HostToolExecutor.swift`. Update the corresponding
`Sources/SwiftStarAppKit/PoolOrchestrator.swift` comment and ensure reads use
the windowed path.

### 2. Make `rereads` measure effective windows

Add the pure counter and tests in
`Sources/SwiftStarKit/ReadRepeatCounter.swift` and
`Tests/SwiftStarKitTests/ReadRepeatCounterTests.swift`. Rewire
`Sources/swiftstar-analyze/main.swift` to report same-window repeats, with
fallback handling for single-session captures and verification against both
committed captures.

### 3. Record the decision

Update the P24 roadmap row and the two P24.1 design records. Treat the pool
change as an instrument change and require a re-baseline before comparing old
`.pool` measurements with new ones.

## Result

Closed 2026-08-30. The measured same-window population was 3 in the control
and 1 after windowing. The single treatment repeat was a bare read followed by
a raw rendering of the same effective window, so a content-withholding guard
would have been dishonest. The read-guard does not return.

The pool `readCache` was deleted and pool reads now use the windowed path. This
landed through `29a0f7a`, `66a7aa7`, and `3faf4a5`; the roadmap/spec decision
record is in `1b21b2e`. The effective-window implementation is referenced by
`Sources/SwiftStarKit/ReadRepeatCounter.swift:1` and
`Sources/SwiftStarAppKit/HostToolExecutor.swift:1`.

The `.pool` behavior changed for every agenttest run, so earlier pool results
are not directly comparable; the cleanup cycle owns the keep/drop/port table
and any required re-baseline.
