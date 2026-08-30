# SwiftStar P24.1 design: the read-guard (`don't-re-read`)

**Date:** 2026-08-30
**Status:** **SUPERSEDED 2026-08-30** by
[`2026-08-30-p24-1-window-honoring-reads-design.md`](2026-08-30-p24-1-window-honoring-reads-design.md).
Do not implement this design.
**Phase:** P24 — Digested first-class tools (feature cycle 1)

> **Why this was withdrawn.** D2 below claims "after any read the model holds
> the whole file," verified by reading `HostToolExecutor.readResult`. The
> verification stopped one call frame short: the immediate caller wraps every
> result in `ToolResultCondenser.condense(raw.text)` at an 8000-byte cap
> (`ToolCallbackResponder.swift:259,284`), so for every file this guard targeted
> the model held a head+tail extract and never the middle. The re-reads it
> counted as redundant are a starvation loop — the model asking 22 different
> ways for a middle it cannot reach. The guard would have answered those asks
> with 25 bytes instead of 8000, cutting Σsuffix by starving the model faster.
>
> Also found, and carried forward as requirements on any successor: no
> invalidation at compaction (the spec's own stated driver) would have made a
> file permanently unobtainable after the first compaction; no escape hatch, in
> a repo that has already recorded a 23-round stall from a refusing tool
> (`ROADMAP.md:337`); `Policy.app` has a third construction site
> (`PoolOrchestrator.swift:208`) that would have silently changed the agenttest
> instrument mid-campaign; and the planned "after" measurement was arithmetically
> incapable of returning anything but the "before" number.
>
> The read guard is not cancelled — it moves to **P24.2**, to be re-decided
> against a measurement taken after windowing lands, together with the pool
> `readCache`, which has the same bug class.

This spec is the authority on P24.1, the first feature cycle of P24. The
phase row ([`ROADMAP.md` P24](../../../ROADMAP.md)) names the read-guard as the
direct fix for the measured 1809 tax; this spec scopes it to one idea and
records the evidence, the design, and the measurement.

Evidence:
[`2026-08-27-1809-prefill-tail-findings.md`](../research/2026-08-27-1809-prefill-tail-findings.md)
(the tax) and
[`2026-08-30-p24-1-read-guard-before-measurement.md`](../research/2026-08-30-p24-1-read-guard-before-measurement.md)
(the reproducible "before" count). Every "what exists" claim below was
verified by direct read on 2026-08-30.

## Problem

One named culprit, measured rather than assumed.

**The sum of prefill tails, taxed by depth.** In the 1809 production capture,
one file — `Sources/SwiftStar/AgentView.swift` (427 lines) — was re-read so
often that its re-reads alone cost **37.5% of the session's Σsuffix**
(29 prefill syncs × exactly 1,809 suffix tokens = 52,461 of 144,631 tokens,
5.7 of the 12.7 prefill minutes), at a per-sync cost that grew 5.9 s → 15.6 s
as context deepened (prefill throughput collapses 519 → 114 tok/s from 0–5k to
25–30k). Compaction churn drives it: five compactions in 24 minutes, each
discarding ~23k tokens, each followed by recovery re-reads of the same file.

The "before" measurement ([`2026-08-30-p24-1-read-guard-before-measurement.md`](../research/2026-08-30-p24-1-read-guard-before-measurement.md),
reproducible via the new `swiftstar-analyze rereads` verb) pins the *count*:

```
worker 0: 76 read/more call(s) across 21 distinct path(s) — 55 redundant re-read(s)
   34  Sources/SwiftStar/AgentView.swift  (windowed: 29)
   11  ROADMAP.md  (windowed: 10)
    …
```

`AgentView.swift` is 34 of 76 calls (32 `read` + 2 `more`, both confirmed to
follow it) → **33 redundant re-reads**; `ROADMAP.md` adds 11/10. Two files are
45 of the 55 redundant reads. The enemy is named, not diffuse.

## What already exists — verified by direct read, do not rebuild

- **The host executor already serves the whole file, ignoring window params.**
  `HostToolExecutor.readResult` reads `FileManager.default.contents(atPath:)`
  and returns the entire file; `start_line`/`max_lines`/`raw`/`whole`/`end_line`
  are parsed into `params` but never consulted
  (`Sources/SwiftStarAppKit/HostToolExecutor.swift:164-196`). This is the fact
  that collapses the coverage design (D2) — after any read the model holds the
  whole file.
- **The pool worker already has a hash read cache.** `Policy.pool` sets
  `readCache: true`; `readResult` SHA256-hashes the bytes, answers an unchanged
  re-read with the generic "(unchanged since last read)", and keys the
  `readCacheStorage` dict by the confinement-resolved path
  (`HostToolExecutor.swift:164-180`). It is per-turn (no turn number, no
  mtime, no `more` handling), and it is **not** the app path: `Policy.app`
  sets `readCache: false`, so the app's own session — where the 1809 tax was —
  has no cache at all.
- **Consent already confines and resolves.** `ToolCallbackResponder.consent`
  confines `read`/`more`/`write`/`list`/`edit`/`search` to the workspace grant
  and carries `resolvedPath` (`ToolCallbackResponder.swift:137-170`); the
  executor re-resolves through the symlink-aware `HostToolConfinement.realPath`
  before every read/write. Two worktrees have disjoint real paths, so a
  path-keyed store is already root-scoped for free (D3).
- **`more` carries no `path` and is currently rejected.** Consent defaults a
  missing `path` param to `"."` (the workspace root,
  `ToolCallbackResponder.swift:141`), so `readResult` tries to read the root
  directory and fails. Verified in the capture: both 1809 `more` calls recorded
  `transitions: ["emitted","rejected"]`. The guard's `more` attribution (D6) is
  therefore a strictly-better side effect, not a behavior we are preserving.
- **The app executor is a per-session singleton, wired through the pure
  responder.** `AgentController.hostToolExecutor` is a `static let`
  (`AgentController.swift:838`); `executeHostTool` (`:843`) is the closure the
  pure `ToolCallbackResponder.respond` injects (`:699`). `inject` already
  resets all per-turn state at turn start — the natural home for the turn
  ordinal (D5).
- **Mutations already carry host-authoritative paths.** `writeResult` and
  `editResult` return `ToolExecutionResult(mutations: [path])`
  (`HostToolExecutor.swift:252,279`), the hook the guard's invalidation rides
  (D4).

## Binding rules (authoritative; not re-openable in this spec)

1. **The wire announces itself** (BRIEF.md rule 7) — not touched: P24.1 adds no
   tool name, no wire field, no engine change, **no recapture** (D7).
2. **Every new test must be shown to fail** when the behavior it pins is broken
   (BRIEF.md rule 2).
3. **A refusal test has a sibling success test** (BRIEF.md rule 4).
4. **The paired-bill guardrail.** A tool's self-reported savings are a claim
   about its counterfactual; the win is measured with `swiftstar-analyze diff`
   on a real session, not asserted (P24 row).

## Scope (strict)

**In.**

- A turn-aware read guard in the **app's own session**: on `read`/`more`, if the
  file's content is unchanged since the session last read it, answer "unchanged
  since turn N" instead of re-serving the file into KV.
- `more` attributed to the last-read path (D6), so it stops erroring.
- Invalidation on the agent's own `write`/`edit` (D4), keyed by the
  confinement-resolved real path (D3).

**Out** (each with a reopen condition, recorded in the ROADMAP backlog).

- **Window-honoring reads** (serving `start_line`/`max_lines` slices instead of
  the whole file). Pre-existing; a *first-read* cost, not the re-read tax P24.1
  attacks. Reopens when the guard is live and a first-read windowed read is
  measured to dominate.
- **Unifying the pool worker's hash cache** with this guard (D8). Reopens as
  P24.1b once the app path is measured.
- **`recall`** and the **deterministic compaction skeleton** (both "sequence
  after P24" per the 1809 findings).

## Design decisions

**D1 — Hash is authoritative; mtime is provenance, not a fast path.** On every
read the executor reads the file and hashes it. The file read is ~1 ms; the
re-read tax it avoids is a 5.9–15.6 s prefill sync — three to four orders of
magnitude apart. Trusting mtime to skip the read would save nothing measurable
and reintroduce a staleness risk (coarse mtime granularity, external edits in
another editor). The store records **both** `hash` and `mtime` (the ROADMAP
names both), but the verdict compares the hash; mtime is recorded for
diagnostics and as the cheap "definitely changed" hint, not as a correctness
gate. This is the same trust boundary the pool's existing cache already uses.

**D2 — The verdict is whole-file, because the executor serves whole files.**
`readResult` serves the entire file regardless of `start_line`/`max_lines`, so
after any read the model holds the whole file and "unchanged since turn N" is
honest for any re-read — full or windowed. The coverage state therefore
collapses to a per-path boolean ("has this session read this path"), with **no
line-range tracking**. This is a simplification of the coverage design
discussed before spec-writing; it is a *fact about the current executor*
(verified above), not a new choice. Window-honoring is out of scope.

**D3 — The store is per-executor-instance, keyed by the real path.** The app
executor is a per-session singleton; the pool executor is a separate instance
(untouched, D8). Keying by `HostToolConfinement.realPath` (symlink-resolved,
workspace-confined) makes two worktrees disjoint keys, and a deleted-then-reused
worktree path a distinct root — no stale entry can leak across roots, and a
mutation in one worktree cannot invalidate another's entry. This is the
worktree requirement stated up front, satisfied structurally rather than by
convention.

**D4 — Invalidation is write/edit-local.** `writeResult`/`editResult` already
return `mutations: [path]`; they now also drop that path's guard entry. External
edits need no invalidation: the next read's hash differs and serves fresh
content. The agent's own rapid edits are covered by the invalidation, not by
mtime.

**D5 — The turn ordinal rides the executor, not the responder.** The
"since turn N" message needs the app session's turn count. The responder's
`execute` closure is `(ToolExecutionRequest) -> …` — a stable, pure P9 interface
— and threading a turn through it would ripple into both `respond` overloads and
both call sites. Instead the executor carries a monotonic `currentTurn` (Int,
default 0) set by `AgentController` once per user turn, recorded into the store
at read time. **Restart must reset it:** `hostToolExecutor` is a `static let`,
so the restart path that already resets `poolState`/`outcomeBuilder`/
`rollingDigest` also calls a new `resetReadGuard()` (clears entries,
`currentTurn`, `lastReadPath`) and zeroes the controller's turn counter.

**D6 — `more` is a re-read of the last-read path.** `more` carries no `path`;
consent defaults it to the workspace root and today the executor errors on it
(verified). The guard attributes `more` to the last path the session read (a
single `lastReadPath` value on the executor, set by each `read`), so an
unchanged `more` answers "unchanged since turn N" instead of erroring.

**D7 — Pure Swift type + the existing seam; zero engine work.** The store and
verdict live in `SwiftStarKit` as a pure type (no I/O, no model, fast-tier
tested); only `HostToolExecutor` does I/O (read/hash/stat) and calls it. No new
tool name, no wire change, no engine patch, **no golden recapture**. P24.1 is
host-side Swift only — the cheapest cycle in the phase by construction.

**D8 — App session only.** The 1809 tax was the app's interactive session, and
that is where the evidence points. The pool worker's existing hash cache stays
as-is; unifying it with the turn-aware guard is a follow-up note (P24.1b), not
part of "one idea at a time."

## Components

### 1. `Sources/SwiftStarKit/ReadGuard.swift` (new, pure)

The store + verdict. No I/O; the caller supplies hash/mtime/path. Fast-tier
testable with synthetic keys.

```swift
public struct ReadGuardEntry: Equatable, Sendable {
    public let hash: String
    public let mtime: Double
    public let turn: Int
}

public enum ReadVerdict: Equatable, Sendable {
    case serve
    case unchanged(sinceTurn: Int)
}

public struct ReadGuard: Sendable {
    public private(set) var entries: [String: ReadGuardEntry]

    public init()
    public mutating func verdict(path: String, hash: String) -> ReadVerdict
    public mutating func record(path: String, hash: String, mtime: Double, turn: Int)
    public mutating func invalidate(path: String)
    public mutating func reset()
}
```

`verdict` returns `.unchanged(sinceTurn:)` iff an entry exists for `path` and
its `hash` equals the supplied hash; otherwise `.serve`. `record` upserts;
`invalidate` removes; `reset` empties. Deterministic and pure — the same inputs
always yield the same verdict.

### 2. `Sources/SwiftStarAppKit/HostToolExecutor.swift` (extend)

- `Policy` gains `readGuard: Bool` (false for `.pool`, true for `.app`). The
  pool's `readCache` hash-only path is unchanged (D8).
- New state: `readGuard: ReadGuard`, `currentTurn: Int = 0`,
  `lastReadPath: String?` — all under the existing `lock`.
- `readResult`, when `policy.readGuard`:
  1. resolve `path = HostToolConfinement.realPath(request)`; on failure, the
     existing "path is outside the workspace grant" refusal.
  2. read bytes; on failure, the existing "could not read \(path)" error.
  3. `hash = SHA256(bytes)`; `mtime = stat(path)`.
  4. `switch readGuard.verdict(path, hash)`:
     - `.unchanged(turn)` → return `ToolExecutionResult(ok: true, text: "unchanged since turn \(turn)")` — a few tokens instead of the file.
     - `.serve` → `readGuard.record(path, hash, mtime, currentTurn)`;
       `lastReadPath = path`; return the full text (as today).
- `more` (no `path`): resolve `path = lastReadPath` before step 1; if nil, the
  existing error. Otherwise identical (D6).
- `writeResult`/`editResult`: on success, `readGuard.invalidate(path)` (D4).
- `resetReadGuard()`: `readGuard.reset()`; `currentTurn = 0`; `lastReadPath = nil`.

### 3. `Sources/SwiftStar/AgentController.swift` (extend)

- A monotonic `turnCounter` (Int), incremented once per user turn in `send`
  (the user-turn entry point; `inject` is shared with internal traffic — worker
  receipts, consulted answers — and must not overcount), written to
  `Self.hostToolExecutor.currentTurn`.
- The restart path (which already resets `poolState`/`outcomeBuilder`/
  `rollingDigest`) additionally calls `Self.hostToolExecutor.resetReadGuard()`
  and zeroes `turnCounter`.

## Cycles

| # | Cycle | Gate | Risk |
|---|---|---|---|
| **1** | `ReadGuard` pure type + fast-tier tests (verdict/record/invalidate/reset matrix; refusal+sibling success per rule 3) | fast tier green, **red first** | none |
| **2** | `HostToolExecutor` wiring: `readGuard` policy, `readResult` guard path, `more` attribution, `lastReadPath`, write/edit invalidation | integration tests (below) green | low |
| **3** | `AgentController` turn counter + restart reset | integration: "since turn N" carries the real turn number; restart clears the store | low |
| **4** | **"After" measurement + research note**: replay the 1809 read sequence through the guard against the files as they exist today → count short-circuits; expect ≈33 of 34 `AgentView.swift` reads. Valid despite any 3-day content drift: the guard's verdict depends only on *within-session* stability — established by the capture's zero mutations (`outcomes.ndjson`: `mutations: []` everywhere) — not on today's content matching 2026-08-27's. Then live paired-bill `swiftstar-analyze diff` at close | note committed; `diff` shows the Σsuffix drop | the phase's one live step |

## Tests (fast tier, no model, no subprocess)

1. **`ReadGuard` matrix** — verdict is `.serve` on first read, `.unchanged(sinceTurn:)`
   on an equal-hash re-read, `.serve` on a changed hash; `record` upserts;
   `invalidate` removes; `reset` empties. A refusal-adjacent case (changed hash)
   gets a sibling success (equal hash) per rule 3.
2. **The message** — "unchanged since turn N" uses the recorded turn, not the
   current one (a stale turn is the bug this pins).

## Integration tier (real files, fake engine — seconds)

3. **Two worktrees sharing a relative path** (the worktree requirement): same
   relative path in two roots; read in both; mutate in one; the other's entry
   survives and still short-circuits. Delete a worktree and reuse its path; the
   new root gets a fresh entry, not a stale short-circuit.
4. **`more` attribution** — a `more` after a `read` of path P consults P's entry
   (unchanged → "unchanged since turn N"); a `more` with no prior read errors as
   today.
5. **Turn counter end-to-end** — turn 1 reads P, turn 2 re-reads unchanged →
   "unchanged since turn 1"; restart clears → turn 1 re-read serves fresh.
6. **Write invalidation** — read P, `edit` P, re-read P → served (not
   "unchanged"), and the entry's hash is the new content.

## Live validation (closure evidence)

- A scripted read-heavy session on the real engine — the 1809 shape (explore this
  repo, re-read the hot file after a compaction) — with the guard on. The
  `rereads` verb still counts the model's 34 `AgentView.swift` requests; the
  guard turns 33 of them into a few-token result. **The claim is measured with
  `swiftstar-analyze diff` against the 1809 baseline capture, not self-reported.**
  Expected: the ~52k-token `AgentView.swift` tail (37.5% of Σsuffix) largely
  gone; the exact ratio is the record, whatever it is.

## Out of scope

Window-honoring reads (see Scope); pool-worker cache unification (D8); `recall`
and the deterministic compaction skeleton (both "sequence after P24"); the
`more`-consent path defaulting to the workspace root (D6 attributes around it
rather than fixing the consent default — that is a separate, larger read-tool
semantics change).

## Note on status

Stamped `proposed` until the cycle ships, then `implemented` (per the P23
spec's note: do not leave a shipped spec mis-stamped).
