# SwiftStar P24.2 design: the read-guard re-decision

**Date:** 2026-08-30
**Status:** proposed
**Phase:** P24 — Digested first-class tools (feature cycle 2)

This spec decides, rather than builds. P24.1 re-scoped
[`2026-08-30-p24-1-window-honoring-reads-design.md`](2026-08-30-p24-1-window-honoring-reads-design.md)
and deferred two items here to be re-decided **against a measurement taken
after windowing lands**:

1. the **read-guard** (`don't-re-read`), and
2. the pool worker's **`readCache`**.

The ROADMAP P24 row states the shared premise: *a hash-keyed "unchanged" answer
is dishonest whenever delivery is partial.* This spec records the post-windowing
measurement, the verdict on each item, and the one tooling fix the verdict
exposes.

Evidence: the paired measurement in
[`2026-08-30-p24-1-window-honoring-after-measurement.md`](../research/2026-08-30-p24-1-window-honoring-after-measurement.md)
and its committed protocol (`Tools/p24-1-measurement/`).

## The measurement (already taken — this spec does not re-run it)

The number that decides the guard question is the **same-window** re-read count:
an identical `(start_line, max_lines)` re-asked on one file. It is *not* the
same-path count, which counts the model's healthy walk across a file as waste.

| | control (pre-P24.1 `readResult`) | treatment (P24.1) |
|---|---|---|
| read/more calls | 12 | 16 |
| distinct `(start_line, max_lines)` windows | 8 | 16 |
| **same-window re-reads** | **3** | **0** |
| repeat rate | 1.38 → loop tripped | 1.00 |

The control's three same-window re-reads are all **bare whole-file re-asks** —
the model asking for the whole file four times because the host ignored its
windows and the condenser cut the middle. That is starvation, not redundancy.
Post-windowing the model asks 8 distinct windows of the hot file and never
repeats once; the closest thing to a repeat is `255/90 → 257/90`, a two-line
walk-forward, not a re-ask.

Capture dirs: treatment
`captures/20260830-104542-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`, control
`captures/20260830-105947-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`.

## Decision 1 — the read-guard does not return

The verdict is not merely "0 re-reads in one session." Each of the guard's
possible benefit cases is empty or self-contradictory:

1. **Same-window short-circuit** (answer `"unchanged since turn N"` to a
   re-ask of content already delivered): the population is measured **0**, and
   the only honest coverage model — per-window, content-addressed, invalidated
   on the agent's own writes *and* on compaction eviction, with an escape
   hatch — is real machinery built to serve nothing. YAGNI.
2. **Delta/coverage serving** (what would catch the `255/90 → 257/90` shift):
   a different, larger mechanism than "the read-guard," and its target is a
   healthy walk-forward, not a loop.
3. **Compaction recovery** (the superseded spec's stated driver): the one case
   where a hash-keyed "unchanged" **lies in the second direction** — after a
   compaction the content was evicted, so "you already have it" is false. An
   honest guard must invalidate on compaction, which removes exactly the
   benefit it was built to deliver.

Every path ends in "build complexity to serve a population of zero, or to lie."
The guard stays retired, and the four requirements the superseded spec's review
carried forward (honest coverage model, compaction invalidation, escape hatch,
a measurement capable of returning non-"before") are moot with it.

**Reopen condition (prose, not a numeric threshold):** if a longer read-heavy
live session — several compactions, multiple files — shows the same-window
re-read population return *as a behavior*, re-open the guard question. A
numeric threshold set after seeing data is what P24.1's falsifier got wrong;
this spec does not repeat it.

## Decision 2 — retire the pool `readCache`; do not make it smarter

The `.pool` branch of `readResult` (`HostToolExecutor.swift:203-221`) has two
defects and they share one fix:

- **whole-file delivery** — the result passes into the 8000-byte condenser and
  becomes head+tail, the same starvation shape P24.1 removed from the app path;
- **the hash-keyed `"(unchanged since last read)"`** — dishonest once delivery
  is partial, and the answer it gives is the same starvation the guard would
  have caused.

"Make it window-honest but keep the hash cache" is rejected: it builds a
content-addressed coverage cache to serve the same-window population measured
at 0, and it re-introduces the invalidation question. The correct fix is to
**delete the cache and unify `.pool` reads on the windowed path** — the pool
worker's `read` becomes byte-identical in behavior to the app's (windowed,
`more` continuation, named errors).

This is an **instrument change**: the `readCache` branch is reached only by the
`swiftstar-agenttest` harness (`PoolOrchestrator` constructs the `.pool`
executor; real pool workers already route through the shared `.app` instance).
Retiring it makes the harness's read path *match the product's*, which is the
direction the cleanup cycle wants, but it must be **recorded in the cleanup
cycle's keep/drop/port table** as a completed divergence-removal, with a
re-baseline note if any measured behavior depends on it. Arm 4 already cannot
pool with arms 1–3 (windowing changed the instrument first), so this does not
perturb an open arm.

## Decision 3 — the `rereads` verb reports same-window repeats

The committed verb currently prints, for the treatment capture:

> `worker 0: 16 read/more call(s) across 4 distinct path(s) — 12 redundant re-read(s)`

`12` is `calls − distinct paths` — a **same-path** count that labels the model's
8 healthy distinct windows of `AgentView.swift` as "7 redundant re-reads." That
is exactly the metric that would re-teach the superseded spec's error, and the
printed word "redundant" contradicts the verb's own doc comment ("read it as a
repeat count, not a waste count").

The verb must report the number this re-decision stands on: **same-window**
repeats, `calls − distinct (path, start_line, max_lines) pairs`, with the
per-path table carrying each path's distinct-window count and repeated-window
multiplicity (the same shape `Tools/window-spread.py` prints). On the treatment
capture the headline becomes `0 same-window re-read(s)`.

## Binding rules (authoritative; not re-openable in this spec)

1. **The wire announces itself** (BRIEF.md rule 7) — not touched: no tool name,
   no wire field, no engine change, no recapture.
2. **Every new test must be shown to fail** when the behavior it pins is broken
   (BRIEF.md rule 2).
3. **A refusal test has a sibling success test** (BRIEF.md rule 4).
4. **No post-hoc numeric thresholds.** The reopen condition above is prose, and
   the `rereads` verb reports a count, not a pass/fail bar. P24.1's falsifier
   was revised after the run tripped it; that failure mode is not repeated.
5. **An instrument change is recorded, not hidden.** The readCache retirement
   is a keep/drop/port entry for the cleanup cycle, stated here and in the
   ROADMAP row, not discovered later.

## Scope (strict)

**In.**

- The recorded measurement and the guard verdict (D1).
- Deleting `Policy.readCache`, `readCacheStorage`, and the `.pool` branch of
  `readResult`; `.pool` reads unify on the windowed path (D2).
- The `rereads` verb's same-window count and per-path window table (D3).

**Out** (each with a reopen condition).

- **The read guard** — retired, not rescheduled; reopens only under the D1
  prose condition.
- **Delta/coverage read serving** — a different mechanism, never scoped.
- **The instrument-reconciliation cleanup cycle** — its own cycle, sequenced
  after this one; this spec only *records* the readCache retirement for it.
- **`recall`** and the **deterministic compaction skeleton** — still "sequence
  after P24."
- **The `more` consent default** (`path` → `"."`) — carried forward from P24.1,
  still out of scope.

## Components

### 1. `Sources/SwiftStarAppKit/HostToolExecutor.swift` (delete, unify)

- Remove `Policy.readCache` (`:47`), the `init` parameter (`:54,57`), the
  `readCache: false`/`readCache: true` literals in `.app`/`.pool` (`:67,76`),
  and `readCacheStorage` (`:84`).
- Delete the `if policy.readCache { … }` branch (`:203-221`). `readResult`
  becomes the single windowed path with no policy fork.
- The `.pool` read error message changes from the folded `"error: could not
  read"` to the app's named `"error: could not read \(path)"`; the separate
  confinement refusal (`"error: path is outside the workspace grant"`) now
  applies to `.pool` too. Both are strictly more informative; no caller
  depends on the folded message.

### 2. `Sources/SwiftStarAppKit/PoolOrchestrator.swift` (one comment)

- The fresh-instance-per-phase comment (`:17`, `:72`) currently cites the old
  `readCache.removeAll()` reset. Its surviving rationale is the vetted-commands
  allowlist and the continuation map dying with the instance; update the
  comment so it does not name a deleted mechanism.

### 3. `Sources/swiftstar-analyze/main.swift` (the verb)

- `ReadRequest` gains the window identity (`start_line`/`max_lines`, or nil for
  a bare read; `more` keeps its existing attribution). Extract this into a pure
  helper so the count is fast-tier testable rather than buried in `main`.
- `cmdRereads` headline becomes `N read/more call(s), D distinct (path, window)
  pairs — R same-window re-read(s)`; the per-path table adds distinct-window
  count and repeated-window multiplicity. `window-spread.py` remains the
  reference implementation to match.

## Cycles

| # | Cycle | Gate | Risk |
|---|---|---|---|
| **1** | Retire `readCache`: delete the policy field, storage, and branch; update the two `.pool`-error tests | build + integration suite green, **red first** | low |
| **2** | `rereads` verb: window identity + same-window count, pure helper + fast-tier tests | fast tier green, **red first**; treatment capture reports `0 same-window re-read(s)` | low |
| **3** | Docs: ROADMAP P24 row (P24.2 decided), superseded-spec cross-references, `rereads` doc comment | commit clean | none |

No live run, no model, no Metal — every cycle is host-side Swift plus docs.
The measurement this spec stands on already exists (see above).

## Tests (fast tier and integration, no model)

1. **`rereads` same-window count** (fast tier, pure helper) — a synthetic read
   list with 2 identical windows re-asked reports `2` same-window re-reads;
   the same list with 2 *different* windows on one path reports `0`. The
   sibling-success/refusal pair per rule 3.
2. **`.pool` read is no longer cached** — read a file twice under
   `.pool(vettedCommands: [])`; the second read returns the file, not
   `"(unchanged since last read)"`. (Replaces
   `poolPolicyReadCachesAnUnchangedFile`.)
3. **`.pool` read honors windows** — a windowed read under `.pool` returns the
   engine-format header and only the requested lines, matching the `.app`
   path. (New: this is the unification the whole cycle exists to make.)
4. **`.pool` read names the path on failure** — `"error: could not read
   <path>"` instead of the folded generic message. (Replaces
   `poolPolicyReadMissingFileUsesGenericMessageWithNoPath`.)
5. `poolPolicyReadCacheInvalidatesOnChange` is deleted with the cache it
   pinned; the "changed file serves new content" behavior is already covered by
   the unified read path's existing tests.

## Out of scope

The read guard (retired); delta/coverage serving; the cleanup cycle itself;
`recall` and the deterministic compaction skeleton; the `more` consent default.

## Note on status

Stamped `proposed` until the cycles ship, then `implemented` (per the P23/P24.1
specs: do not leave a shipped spec mis-stamped).

## Documents this spec invalidates

Correct these when the cycle lands:

1. The **P24 row** in [`ROADMAP.md`](../../../ROADMAP.md) — its status cell says
   "P24.2 + instrument-reconciliation cleanup cycle remain"; after this cycle it
   must record P24.2's verdict (guard retired, `readCache` retired as an
   instrument change) and leave only the cleanup cycle.
2. [`2026-08-30-p24-1-window-honoring-reads-design.md`](2026-08-30-p24-1-window-honoring-reads-design.md)
   — its scope section files the read-guard and `readCache` to P24.2; add a
   pointer to this spec as the resolution.
3. [`2026-08-30-p24-1-read-guard-design.md`](2026-08-30-p24-1-read-guard-design.md)
   — already `SUPERSEDED`; its "moves to P24.2" note now resolves here.
4. `Sources/swiftstar-analyze/main.swift` — the `ReadRequest`/`cmdRereads` doc
   comments assert the same-path count; they change with the verb.
