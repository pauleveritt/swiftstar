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

A third item arrives from the window-honoring spec's D5: the continuations-map
eviction rule, decided in Scope below.

The ROADMAP P24 row states the shared premise: *a hash-keyed "unchanged" answer
is dishonest whenever delivery is partial.* This spec records the post-windowing
measurement, the verdict on each item, and the one tooling fix the verdict
exposes.

Evidence: the paired measurement in
[`2026-08-30-p24-1-window-honoring-after-measurement.md`](../research/2026-08-30-p24-1-window-honoring-after-measurement.md)
and its committed protocol (`Tools/p24-1-measurement/`).

## The measurement (already taken — this spec does not re-run it)

The number that decides the guard question is the **same-window** re-read count:
the *same effective window* of the same path asked again. The key is the
**effective** window, not the raw parameters: `start_line` absent resolves to 1,
`max_lines` absent resolves to the engine's context tier (500 at the app's
32768), and `raw`/`whole` are *not* part of the key (they change the rendering,
not the covered lines). A bare read and `start=1,max=500` therefore collide —
they deliver the same head of the file — and that collision is the point of
measuring this way. It is *not* the same-path count, which counts the model's
healthy walk across a file as waste.

| | control (pre-P24.1 `readResult`) | treatment (P24.1) |
|---|---|---|
| read calls (`more` separate) | 11 | 16 |
| distinct effective `(path, start_line, max_lines)` windows | 8 | 15 |
| **same-window re-reads** | **3** | **1** |
| repeat rate | 1.38 → loop tripped | 1.07 |

The control's three same-window re-reads are four **bare whole-file re-asks**
(4 asks of one effective window = 3 repeats) — the model asking for the whole
file over and over because the host ignored its windows and the condenser cut
the middle. That is starvation, not redundancy. The treatment's single
same-window re-read is a **bare read of `AgentView.swift` followed by a raw
`start=1,max=500` of the same file**: the same head of the file asked twice, the
second time in raw form. It is one duplicate delivery in the whole session, and
it is itself a case a hash-keyed guard would mis-handle (see D1). The remaining
reads are a healthy walk — 8 distinct windows of the hot file, the closest to a
repeat being `255/90 → 257/90`, a two-line walk-forward.

Capture dirs: treatment
`captures/20260830-104542-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`, control
`captures/20260830-105947-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`.

## Decision 1 — the read-guard does not return

The verdict rests on a population measured at **1**, not 0, and on the shape of
that one. The guard's *withholding* forms (answer "unchanged" instead of
serving) are each empty or self-contradictory:

1. **Same-window short-circuit** (answer `"unchanged since turn N"` to a
   re-ask of content already delivered): the population is **1** — and that one
   is a bare read followed by a **raw** `start=1,max=500`. A hash-keyed guard
   would have to answer "unchanged" to a request for a *different rendering*
   (raw), withholding bytes the model explicitly asked for — which is not a
   clean short-circuit at all. The only honest coverage model — per-window,
   content-addressed, invalidated on the agent's own writes *and* on compaction
   eviction, with an escape hatch — is heavy machinery built to serve one
   ambiguous event. YAGNI.
2. **Delta/coverage serving** (what would catch the `255/90 → 257/90` shift):
   a different, larger mechanism than "the read-guard," and its target is a
   healthy walk-forward, not a loop.
3. **Compaction recovery** (the superseded spec's stated driver): the one case
   where a hash-keyed "unchanged" **lies in the second direction** — after a
   compaction the content was evicted, so "you already have it" is false. An
   honest guard must invalidate on compaction, which removes exactly the
   benefit it was built to deliver.

There is a fourth shape the above does not cover, and it is honest: an
**informational** note — serve the window and append "unchanged since turn N
(hash X)" — which withholds nothing and leaves the model the decision. The
codebase already has this shape: the pool harness's refusal-streak hint
(`PoolOrchestrator.swift:144-156`) appends a hint to a refusal rather than
silently refusing. This spec does not build it: it is a hint, not the
content-withholding "read-guard" this re-decision is about, and its one
candidate event (the raw re-ask above) the model already resolved without help.
It stays out of scope, recorded below, not silently dropped.

The guard stays retired. The four requirements the superseded spec's review
carried forward (honest coverage model, compaction invalidation, escape hatch,
a measurement capable of returning non-"before") are moot with it.

**Reopen condition (prose, not a numeric threshold):** if a longer read-heavy
live session — several compactions, multiple files — shows the same-window
re-read population return *as a behavior*, re-open the guard question. A
numeric threshold set after seeing data is what P24.1's falsifier got wrong;
this spec does not repeat it.

## Decision 2 — retire the pool `readCache`; do not make it smarter

The `.pool` branch of `readResult` (`HostToolExecutor.swift:203-223`) has two
defects and they share one fix:

- **whole-file delivery** — the result passes into the 8000-byte condenser and
  becomes head+tail, the same starvation shape P24.1 removed from the app path;
- **the hash-keyed `"(unchanged since last read)"`** — dishonest once delivery
  is partial, and the answer it gives is the same starvation the guard would
  have caused.

"Make it window-honest but keep the hash cache" is rejected: it builds a
content-addressed coverage cache to serve a same-window population measured
at 1, and it re-introduces the invalidation question. The correct fix is to
**delete the cache and unify `.pool` reads on the windowed path** — the pool
worker's `read` becomes byte-identical in behavior to the app's (windowed,
`more` continuation, named errors).

This is an **instrument change**: the `readCache` branch is reached only by the
`swiftstar-agenttest` harness (`PoolOrchestrator` constructs the `.pool`
executor; real pool workers already route through the shared `.app` instance).
Retiring it makes the harness's read path *match the product's*, which is the
direction the cleanup cycle wants — but it changes what `.pool` worker-phase
reads return in **every** agenttest run (whole-file + "unchanged" → windowed),
so `.pool` results are no longer comparable to *any* earlier run's, not just to
arm 4's. This must be **recorded in the cleanup cycle's keep/drop/port table**
as a completed divergence-removal **with a re-baseline note covering all prior
`.pool` measurements** (arm 4 was already severed from arms 1–3 by windowing;
this severs the `.pool` worker-phase path from every pre-P24.2 capture).

## Decision 3 — the `rereads` verb reports same-window repeats

The committed verb currently prints, for the treatment capture:

> `worker 0: 16 read/more call(s) across 4 distinct path(s) — 12 redundant re-read(s)`

`12` is `calls − distinct paths` — a **same-path** count that labels the model's
8 healthy distinct windows of `AgentView.swift` as "7 redundant re-reads." That
is exactly the metric that would re-teach the superseded spec's error, and the
printed word "redundant" contradicts the verb's own doc comment ("read it as a
repeat count, not a waste count").

The verb must report the number this re-decision stands on: **same-window**
repeats of the **effective** window — `start_line ?? 1` and `max_lines ?? tier`,
so a bare read and `start=1,max=500` collide — with the per-path table carrying
each path's distinct-window count and repeated-window multiplicity (the same
shape `Tools/window-spread.py` prints, but with defaults resolved). On the
treatment capture the headline becomes `1 same-window re-read(s)` (the bare +
raw `start=1,max=500` pair), not `12`.

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
- **The continuations-map eviction question (inherited from P24.1 D5): decided
  — no eviction rule.** Worktree roots are UUID-named and never reused, so a
  completed turn's entry can never be hit again; the map's growth is bounded by
  the number of dispatched turns since restart and each entry is a few scalars.
  An eviction rule would need turn-boundary knowledge the executor does not
  have, for zero correctness benefit. Accepted as-is.

**Out** (each with a reopen condition).

- **The read guard** — retired, not rescheduled; reopens only under the D1
  prose condition.
- **The informational "unchanged" hint** (D1's fourth shape) — a note appended
  to a served read, not a guard; not built, population ≈ 1.
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

### 3. `Sources/SwiftStarKit/ReadRepeatCounter.swift` (new, pure) + `main.swift`

- The window key is the **effective** window: `start_line ?? 1`, `max_lines ??
  ReadWindow.defaultLines(contextSize:)`, computed in a pure `ReadRepeatCounter`
  in `SwiftStarKit` (fast-tier tested) so the bare≡`start=1,max=<tier>` rule is
  pinned by a test, not an assumption. `raw`/`whole` are not in the key.
- `readRequests` captures `ctx_size` from the wire's `status` events and passes
  it through; `more` is attributed to a path but excluded from the count.
- `cmdRereads` headline becomes `N read call(s), D distinct (path, window)
  pairs — R same-window re-read(s) [M more call(s)]`; the per-path table adds
  distinct-window count and repeated-window multiplicity, sorted deterministically
  (calls desc, then path asc). `window-spread.py` remains the reference to
  cross-check against (it does not resolve bare reads; the verb does).

## Cycles

| # | Cycle | Gate | Risk |
|---|---|---|---|
| **1** | Retire `readCache`: delete the policy field, storage, and branch; update the two `.pool`-error tests | build + integration suite green, **red first** | low |
| **2** | `rereads` verb: effective-window key + same-window count, pure helper + fast-tier tests | fast tier green, **red first**; treatment capture reports `1 same-window re-read(s)` | low |
| **3** | Docs: ROADMAP P24 row (P24.2 decided), superseded-spec cross-references, `rereads` doc comment | commit clean | none |

No live run, no model, no Metal — every cycle is host-side Swift plus docs.
The measurement this spec stands on already exists (see above).

## Tests (fast tier and integration, no model)

1. **`ReadRepeatCounter` same-window count** (fast tier, pure) — identical
   windows re-asked report the repeat count; distinct windows on one path
   report 0; **a bare read and `start=1,max=<tier>` collide** (the effective-key
   rule the whole metric rests on); the same window on different paths does not
   collide. Sibling-success/refusal pairs per rule 3.
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
5. **`.pool` confinement refusal** — an out-of-grant read under `.pool` now
   refuses with `"error: path is outside the workspace grant"` (new behavior,
   new test); its sibling success is test 3, per rule 3.
6. `poolPolicyReadCacheInvalidatesOnChange` is deleted with the cache it
   pinned; the "changed file serves new content" behavior is already covered by
   the unified read path's existing tests.

## Out of scope

The read guard (retired); the informational "unchanged" hint (D1's fourth
shape); delta/coverage serving; the cleanup cycle itself; `recall` and the
deterministic compaction skeleton; the `more` consent default. The
continuations-map eviction rule is **decided, not deferred** — see Scope.

## Note on status

Stamped `proposed` until the cycles ship, then `implemented` (per the P23/P24.1
specs: do not leave a shipped spec mis-stamped).

## Documents this spec invalidates

Correct these when the cycle lands:

1. The **P24 row** in [`ROADMAP.md`](../../../ROADMAP.md) — **both** cells. The
   status cell still says "P24.2 + instrument-reconciliation cleanup cycle
   remain"; it must record P24.2's verdict (guard retired, `readCache` retired
   as an instrument change) and leave only the cleanup cycle. The **description
   cell** still lists the read-guard as a P24 tool and the `readCache` as kept;
   both must be marked retired there too, or the row keeps scheduling a decided
   item.
2. [`2026-08-30-p24-1-window-honoring-reads-design.md`](2026-08-30-p24-1-window-honoring-reads-design.md)
   — its scope section files the read-guard and `readCache` to P24.2; add a
   pointer to this spec as the resolution.
3. [`2026-08-30-p24-1-read-guard-design.md`](2026-08-30-p24-1-read-guard-design.md)
   — already `SUPERSEDED`; its "moves to P24.2" note now resolves here.
4. `Sources/swiftstar-analyze/main.swift` — the `ReadRequest`/`cmdRereads` doc
   comments assert the same-path count; they change with the verb.
