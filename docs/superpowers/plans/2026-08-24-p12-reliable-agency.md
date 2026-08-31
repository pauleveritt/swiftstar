---
phase: P12
cycle: P12-reliable-agency
lifecycle: closed
---

# P12 Reliable Agency implementation plan

## Goal

Build a host-owned agency loop around one model: typed phase packets, bounded
tools, real validation, and recovery. Measure writes and acceptance outcomes,
not tool-call counts.

## Work completed

- Define the phase packet and role boundaries in the SwiftStarKit/AppKit seams.
- Implement the decompose, implement, and repair roles with explicit writable
  files, validation, and receipt handling.
- Add bounded tool admission, worktree transaction handling, and cumulative
  recovery behavior.
- Record live evidence and the P12.4/P12.5/P12.7/P12.8 follow-on decisions in
  the linked research documents.

## Verification

The fast tier remains fixture-driven. Live claims are limited to the small-n
captures recorded in the research trail; a model's prose is not evidence of a
write or a passing acceptance suite.

## Result

Closed 2026-08-25. All three roles were evidenced live at least once, with
decompose closed through P12.5. The implementation and recovery machinery is
recorded in `Sources/SwiftStarAppKit/PhaseRepair.swift:1`,
`Sources/SwiftStarAppKit/RepairLoop.swift:1`, and the associated dispatch
types/tests. P12.8's live phase-boundary confirmation and P12.0/P12.7 remain
open, non-blocking follow-ups as recorded in `ROADMAP.md` and the linked
research records; they are not silently reclassified as evidence of success.

The plan's detailed implementation bodies remain available in Git history.
The current durable decision trail is
`docs/superpowers/research/goal-ledger-v3.md` and
`docs/superpowers/research/2026-08-26-overnight-80-cell-verdict.md`.
