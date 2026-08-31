---
phase: P24
cycle: P24.1-window-honoring-reads
lifecycle: closed
---

# P24.1 Window-Honoring Reads Implementation Plan

## Goal

Make host-served reads honor the engine's `start_line`, `max_lines`, `whole`,
and `raw` contract, continue with `more`, and keep rendered results below the
tool-result budget. This replaces the withdrawn read-guard design.

## Work completed

### 1. Correct the surrounding record

Update the withdrawn plan, before-measurement note, analyzer wording, design
spec, and roadmap pointers so that the recorded premise is starvation caused
by partial delivery rather than proven redundant reads.

### 2. Implement the pure window renderer

Create `ReadWindow` in `Sources/SwiftStarKit/ReadWindow.swift` and its fast-tier
tests in `Tests/SwiftStarKitTests/ReadWindowTests.swift`. Cover line ranges,
byte budgets, CR/CRLF numbering, over-budget lines, raw mode, whole mode, and
context-sized defaults.

### 3. Wire the host executor

Update `Sources/SwiftStarAppKit/HostToolExecutor.swift` and its integration
tests so app reads render windows, retain continuation state per workspace,
return named errors, and use the engine-compatible `more` behavior. Keep the
pool path and agenttest instrumentation explicitly visible for the later
reconciliation cycle.

### 4. Verify and record

Run the fast tier, the host-tool capture, the paired control, and the
after-measurement analysis. Commit the protocol and evidence before closing
the cycle.

## Result

Closed 2026-08-30. The implementation landed through the P24.1 commits
`f2c0c5a`, `0ce679c`, `812b8bf`, `6dd75a9`, and `b99c71a`, with the host-tool
measurement and review fixes recorded alongside them. The paired control
reproduced the pre-windowing loop: 12 reads of one file and a timeout on the
first prompt; the treatment used 3 reads and completed all 12 prompts. The
numeric falsifier was revised after seeing the treatment and is therefore
post-hoc, not claimed as preregistered evidence. Full caveats and captures are
in `docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md`.

The roadmap records 799 tests, the six engine-parity corrections, and the
remaining P24.2 instrument decision. The former read-guard plan is superseded;
the durable implementation references are
`Sources/SwiftStarKit/ReadWindow.swift:1` and
`Sources/SwiftStarAppKit/HostToolExecutor.swift:1`.
