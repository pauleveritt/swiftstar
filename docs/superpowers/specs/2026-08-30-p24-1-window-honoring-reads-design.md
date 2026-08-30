# SwiftStar P24.1 design: window-honoring reads

**Date:** 2026-08-30
**Status:** implemented (2026-08-30). A paired control arm (only `readResult`
reverted) reproduced the loop on demand: 12 reads of one file and a turn killed
at the 240 s timeout, against 3 reads and a completed turn. **The numeric
falsifier is post-hoc, not pre-registered** — the committed threshold was
revised after the treatment tripped it; see the
[after-measurement](../research/2026-08-30-p24-1-window-honoring-after-measurement.md),
which also records that the measurement protocol is not yet reproducible from
the repo
**Phase:** P24 — Digested first-class tools (feature cycle 1)

This spec **supersedes**
[`2026-08-30-p24-1-read-guard-design.md`](2026-08-30-p24-1-read-guard-design.md).
That spec proposed a re-read guard on the premise (its D2) that "after any read
the model holds the whole file." Review on 2026-08-30 falsified the premise: the
executor's whole-file text passes through `ToolResultCondenser.condense` at an
8000-byte cap before it reaches the model, so for every file the guard targeted
the model held a head+tail extract, never the middle. The re-read tax it aimed
at is not redundancy — it is a starvation loop. This spec attacks the loop; the
guard is re-decided in P24.2 against a fresh measurement.

Evidence:
[`2026-08-27-1809-prefill-tail-findings.md`](../research/2026-08-27-1809-prefill-tail-findings.md)
(the price) and
[`2026-08-30-p24-1-read-guard-before-measurement.md`](../research/2026-08-30-p24-1-read-guard-before-measurement.md)
(the count — note its "Two facts" §2 is the fact this spec acts on, and its §1
framing of those reads as redundant is what review overturned). Every "what
exists" claim below was verified by direct read on 2026-08-30, at the immediate
caller as well as the callee — the failure mode of the superseded spec.

## Problem

The model cannot obtain the middle of a file, so it asks over and over.

The engine advertises a windowed `read` — `start_line`, `max_lines`, `whole`,
`raw` (`external/ds4/ds4_agent.c:1320-1330`) — and its system prompt instructs
the model to use it: *"read path alone returns a context-sized bounded chunk,
not the whole file; for first looks at large files, prefer max_lines around
80-160"* and *"If read says more lines are available, call more with
count=<lines> to read the next chunk"* (`:1454-1455`, repeated `:1582`,
`:1645`). The result is documented to carry `continue_offset=N` (`:1188`).

Under `--host-tools` — which the app always passes
(`Sources/SwiftStarKit/AgentCommand.swift:105`) — none of that is true. The host
ignores every window parameter and returns the entire file
(`Sources/SwiftStarAppKit/HostToolExecutor.swift:182-191`), and the responder
then condenses that text to 8000 bytes as head + `[truncated: N of M bytes
shown]` + tail (`Sources/SwiftStarKit/ToolCallbackResponder.swift:259,284` →
`Sources/SwiftStarKit/ToolResultCondenser.swift:19`). The middle of any file
over 8000 bytes is unreachable **by construction**: every window request returns
the same head and tail.

The 1809 capture is that loop. `Sources/SwiftStar/AgentView.swift` was 19,736
bytes; the model issued 32 `read` calls against it, 27 windowed, in 22 distinct
windows almost all centred on lines 240–320 — including `start_line: 252,
max_lines: 20`, the model shrinking the ask to twenty lines hoping anything
comes back:

```
5×  (no window)   2× 200/100  2× 252/80   2× 252/100  2× 250/50   2× 252/50
2×  250/100       1× 100/100  1× 270/100  1× 320/80   1× 1/50     1× 320/50
1×  250/80        1× 248/60   1× 240/60   1× 240/100  1× 252/20   1× 252/30
1×  240/150       1× 250/150  1× 1/250    1× 252/200
```

Its own think stream names the cause: *"File is 19736 bytes, need to read lines
252+ to see bottomStatusBar implementation - File appears to be truncated in
read output"*; twenty further events say *"is still truncated"*. The byte count
19736 exists in its context only via the condenser's marker.

This also explains the trace signature the 1809 findings priced: **30 prefill
syncs with suffix exactly 1,809 tokens**. A constant suffix across 22 different
requested windows is only explicable by a fixed-size result — 8000 bytes of
Swift ≈ 1,810 tokens. The 37.5% of Σsuffix is the cost of the loop, not the
cost of redundancy.

## What already exists — verified by direct read, do not rebuild

- **The engine implements the whole contract.** `agent_read_range`
  (`ds4_agent.c:8102-8174`) resolves the range, renders it, and sets the `more`
  continuation. Header when truncated (`:8148-8152`):
  `"<path>: lines A-B of N; continue_offset=C; call more with count=K to read
  the next chunk\n"`; at EOF (`:8154`): `"<path>: lines A-B of N\n"`. Body lines
  carry a `"%d "` 1-based prefix (`:8160-8163`). `raw`/bare mode emits the bytes
  plus `"[Read truncated at line X of N. continue_offset=C. Call more with
  count=K to read the next chunk.]\n"` (`:8138-8143`). This spec ports these
  strings verbatim; it does not design new ones.
- **The engine clears `more` state at EOF.** `:8168-8170` — a truncated read
  sets `(path, end_idx+1, bare)`, a read that reached EOF sets `(NULL, 0,
  false)`, so `agent_tool_more` (`:8230`) answers *"no previous output to
  continue"* rather than inventing a continuation. Honest by construction; the
  host must copy this, not just the happy path.
- **Chunk defaults are tiered off context size.** `agent_read_default_lines`
  (`:8090`) returns 120 / 240 / 500 for ctx ≤8192 / ≤16384 / else
  (`:7885-7889`). The app's `contextSize` defaults to 32768
  (`AgentCommand.swift:70`, passed as `-c` at `:105`) → the 500-line tier.
- **Every host tool result is condensed at 8000 bytes.**
  `ToolCallbackResponder.respond` wraps `execute`'s text in
  `ToolResultCondenser.condense(raw.text)` on both paths
  (`ToolCallbackResponder.swift:259,284`); the default `limit` is 8000 and no
  caller overrides it (`ToolResultCondenser.swift:19`). This is the constraint
  the engine never faces and the superseded spec never reached.
- **Confinement already resolves and refuses.** `HostToolConfinement.realPath`
  (`HostToolConfinement.swift:20`, `:27`) is symlink-aware and workspace-
  confined; the executor calls it before every read.
- **The `.app` executor is process-lifetime and shared.**
  `AgentController.hostToolExecutor` is a `nonisolated private static let`
  (`AgentController.swift:838`); pool workers route through the same instance
  (`AgentPoolTurnLoop.swift:138` passes `execute: Self.executeHostTool`), and
  the agenttest harness constructs a second `.app`-policy executor
  (`PoolOrchestrator.swift:208`). It is **not** a per-session singleton — any
  per-session scalar on it is shared across the main agent and every worker.
  This is why D5 keys continuation state rather than storing a scalar.
- **`more` reaches `readResult` today and always errors.** `HostToolExecutor`
  dispatches `"read", "more"` to the same function (`:134-136`); consent
  defaults a missing `path` to `"."` (`ToolCallbackResponder.swift:144`), which
  resolves to the workspace root, so the read of a directory fails. Confirmed
  in the capture: both 1809 `more` calls recorded
  `transitions: ["emitted","rejected"]`.

## Binding rules (authoritative; not re-openable in this spec)

1. **The wire announces itself** (BRIEF.md rule 7) — not touched: P24.1 adds no
   tool name, no wire field, no engine change, **no recapture** (D8).
2. **Every new test must be shown to fail** when the behavior it pins is broken
   (BRIEF.md rule 2).
3. **A refusal test has a sibling success test** (BRIEF.md rule 4).
4. **Verification reaches the immediate caller.** A claim about what the model
   receives is not established by reading the function that returns the text;
   it is established by following the text to the wire. This rule exists
   because its violation is what invalidated the superseded spec.
5. **The success criterion is behavioral, not a token count.** A tool that
   starves the model faster reduces Σsuffix. The claim is that the pathology
   disappears (D9).

## Scope (strict)

**In.**

- `read` honors `start_line` / `max_lines` / `whole` / `raw`, rendered in the
  engine's exact result format, with a byte budget that keeps every result
  under the condenser cap (D2).
- `more` continues the calling workspace's last truncated read, and errors when
  there is none (D4, D5).
- `contextSize` threaded into the executor so the line default matches the
  engine's tier (D3).

**Out** (each with a reopen condition).

- **The read guard** (`don't-re-read`). Reopens as **P24.2**, re-decided against
  a "before" measurement taken *after* windowing lands — the prior one measured
  the starvation loop and counted its repeats as redundancy. If it returns it
  needs an honest coverage model, compaction invalidation, and an escape hatch;
  see the superseded spec's review findings.
- **The pool worker's `readCache`** (`HostToolExecutor.swift:161-181`). It
  answers `"(unchanged since last read)"` on a whole-file hash match — the same
  dishonesty, one bug class: *a hash-keyed "unchanged" answer is wrong whenever
  delivery is partial.* Untouched here to keep one idea per cycle; reopens with
  P24.2, which decides both together.
- **The `more` consent default** (`path` → `"."`). D4 attributes around it
  rather than changing read-tool consent semantics.
- **`recall`** and the **deterministic compaction skeleton** (both "sequence
  after P24").

## Design decisions

**D1 — Port the engine's contract verbatim; do not design a new one.** The
model's system prompt already describes `continue_offset`, the `lines A-B of N`
header, and `more with count=`. The host's job is to make those sentences true.
Result strings, the `"%d "` line prefix, the bare-mode note, and the EOF-clears-
`more` rule are copied from `agent_read_range` (`ds4_agent.c:8102-8174`). A
divergence here would be a second contract for the same tool name, which is the
fork-ledger's worst case. **Ledger entry:** *host mirrors engine read semantics,
plus a byte budget the engine does not need (D2).*

**D2 — The window is bounded by bytes as well as lines, and the byte bound
wins.** The engine's 500-line default is ~20 KB of dense Swift; condensed at
8000 bytes it reproduces the starvation loop exactly, so honoring the line
params alone does not fix the bug. The renderer therefore stops emitting when
the total rendered output (header included) would exceed **7000 bytes**, and
reports `continue_offset` at the line it actually stopped on. `max_lines` and
`whole: true` are **ceilings, not guarantees**.

The invariant this buys, and the reason it is the centre of the design:

> **The header's line range always names exactly the lines present in the body,
> and the result never exceeds the condenser's limit.**

So `condense` becomes a no-op on read results instead of the thing that silently
removes the middle. The 1000 bytes of slack under the 8000 cap absorb the header
(bounded by path length + ~160) with room to spare.

**The budget scales with context, because a constant is incoherent at 4k.**
`defaultLines` already tiers off context size; a fixed byte budget alongside it
would not. At `contextSize: 4096` — the AFM tier the watcher-tier Backlog entry
anticipates — 7000 bytes is ~1,750 tokens, **half the model's entire context in
one tool result**, and 120 lines of dense Swift is routinely 6–8 KB, so the byte
bound would bind and deliver exactly that. The rule is therefore

```
byteBudget(contextSize) = min(7000, max(1024, contextSize / 2))
```

— `contextSize / 2` bytes is ≈ `contextSize / 8` tokens, so one tool result is
~12.5% of context at any tier; the 7000 ceiling is the condenser's cap, and the
1024 floor keeps a pathological setting from starving the read entirely. At the
app's 32768 this is 7000 and nothing changes; at 4096 it is 2048.

This does not make small-context models *good* at reading large files — see D9's
note on pagination thrash — it makes the budget honest at every tier instead of
hard-coding a 32k assumption into the tool contract.

**D3 — The line default mirrors the engine's tier, so `contextSize` reaches the
executor two ways.** `HostToolExecutor` computes 120 / 240 / 500 by the engine's
thresholds. Diverging on the default would put two different numbers behind one
tool name for no gain.

The two construction sites need different mechanisms, because one of them has no
settings yet:

- `PoolOrchestrator` (`:19`, `:80`, `:208`) constructs per phase with its config
  in hand → an `init(policy:contextSize:)` parameter, defaulting to 32768.
- `AgentController.hostToolExecutor` (`:838`) is a **`static let`**, initialized
  at type-initialization before any `settings` exist. It cannot take the value at
  construction. It gets `setContextSize(_:)`, called from the session
  start/restart block from the same `settings.contextSize` that builds the `-c`
  argument (`AgentCommand.swift:105`) — the block that already calls
  `resetReadState()`.

Both paths land in the same stored property. The default keeps every existing
construction site compiling and behaving identically to the engine's large tier.

**Per-worker override (added 2026-08-30 after review).** The engine tiers off
*the worker's* effective context (`agent_read_default_lines` takes
`agent_worker_effective_ctx_size(w)`), and P23 gave pool workers their own
context, clamped to `[4096, parent]`. Since every worker shares the one `.app`
executor, a single scalar would hand a 4k worker the parent's 500-line,
7000-byte windows — exactly the incoherence D2 argues against. So the executor
also carries `setContextSize(_:forRoot:)`, keyed by worktree root (already
disjoint per worker, D5), and `AgentPoolTurnLoop` registers each worker's
context at turn start.

**D4 — `more` is the engine's `more`: a continuation, not a re-read.** A
truncated read records the continuation `(path, nextLine, bare)`; a read that
reaches EOF **clears** it. `more` reads `count` lines (default: the same tier)
from the recorded line; with no recorded continuation it returns *"error: no
previous output to continue"*. `more` therefore always makes progress or
honestly refuses — it can never answer "you already have this."

**D5 — Continuation state is keyed by workspace root, not stored as a scalar.**
The `.app` executor is shared by the main agent, `/chat` and dispatched workers
(`AgentPoolTurnLoop.swift:138`), so a single `lastRead` scalar would let a
worker's read retarget the main agent's next `more`. State is
`[String: Continuation]` keyed by `request.workspace`'s resolved root. Workers
run in per-turn UUID worktrees (`WorktreeDispatcher.swift:42-43`), so roots are
disjoint for free. Entries are dropped on `resetReadState()` at session start /
restart. They are **not** dropped when a worktree turn ends — an earlier draft
of this decision claimed they were, and no such cleanup was ever written. It is
harmless (worktree roots are UUID-named, so a stale key can never be hit again)
but it means the map grows with dispatched turns until a restart; an eviction
rule is P24.2's to decide alongside the rest of the read state.

**D6 — Progress is guaranteed even for a single over-budget line.** A line
longer than the budget would otherwise emit nothing and leave `continue_offset`
unmoved — an infinite `more` loop. The renderer always emits at least one line;
when that line alone exceeds the budget it is truncated **by the renderer** at
the budget with a `"[line N truncated at M of K bytes]"` marker, and
`continue_offset` advances to N+1. The truncation is named in-band and stays
under the condenser cap, so the D2 invariant holds: partial delivery is always
self-declaring.

**D7 — Windowing lands on the app read path only; the `readCache` branch is
untouched.** `readResult` forks on `policy.readCache` (`:161`): the `.pool`
branch hash-caches and returns whole files, the `.app` branch returns whole
files plainly. This spec changes only the second. The `.pool` branch therefore
keeps *both* of its defects — whole-file delivery into a condenser, and a
hash-keyed `"(unchanged since last read)"` that is dishonest once delivery is
partial — and both are filed to P24.2, which decides them together with the read
guard (one bug class, one cycle). This is a scope boundary, not a claim that the
pool path is correct.

The boundary costs less than it appears: real pool workers do not use a
`.pool`-policy executor. They route through the shared `.app` instance
(`AgentPoolTurnLoop.swift:138`), so dispatched workers and `/chat` get windowing
from this cycle.

**D8 — Pure renderer + the existing seam; zero engine work.** The window
arithmetic and rendering live in `SwiftStarKit` as a pure type (no I/O,
fast-tier tested); `HostToolExecutor` does the file read and owns the
continuation map. No new tool name, no wire change, no engine patch, no golden
recapture.

**D9 — The success criterion is the disappearance of the pathology.** Windowing
makes results smaller, so Σsuffix will fall for reasons that prove nothing.
The measured claim is the shape of the read sequence: **many distinct windows
clustered on one region of one file is the signature of the loop, and it must be
gone.** A Σsuffix *increase* is an acceptable outcome if the turn now completes —
that is the paired-bill guardrail applied honestly rather than as a token race.

**A limit this cycle does not remove: pagination thrash at small context.**
Windowing makes a large file *reachable* by a small-context model; it does not
make it *practical*. At `contextSize: 4096`, a 427-line file is four windows of
~500 tokens each (D2's scaled budget), and the model compacts between them — it
has lost window 1 before it reaches window 3. That is the starvation loop
wearing a different hat, and `more`-pagination is the wrong primitive for it.
The right one is targeted retrieval: locate the line, then read one small window
around it — which is what P24's `scout` is for. **Reopen condition:** when the
ANE/AFM tier's falsifiers pass and a small-context worker is real, measure a
paginated read on it before assuming windowing serves that tier.

## Components

### 1. `Sources/SwiftStarKit/ReadWindow.swift` (new, pure)

```swift
public struct ReadWindowRequest: Equatable, Sendable {
    public let startLine: Int          // 1-based; clamped to ≥ 1
    public let maxLines: Int?          // nil → caller's tier default
    public let whole: Bool
    public let raw: Bool
}

public struct ReadWindowResult: Equatable, Sendable {
    public let text: String            // header + body, ≤ byteBudget
    public let nextLine: Int?          // continuation line, nil at EOF
    public let lastLine: Int           // last line present in the body
    public let totalLines: Int
}

public enum ReadWindow {
    public static func render(
        text: String, path: String, request: ReadWindowRequest,
        defaultLines: Int, byteBudget: Int = 7000
    ) -> ReadWindowResult

    /// The engine's tier (ds4_agent.c:8090, :7885-7889).
    public static func defaultLines(contextSize: Int) -> Int

    /// D2: min(7000, max(1024, contextSize / 2)) — one tool result is ~12.5%
    /// of context at any tier, never half of a 4k window.
    public static func byteBudget(contextSize: Int) -> Int
}
```

Pure and deterministic: same inputs, same output. `nextLine == nil` is the
signal the executor uses to clear the continuation (D4).

### 2. `Sources/SwiftStarAppKit/HostToolExecutor.swift` (extend)

- `init(policy:contextSize:)` — `contextSize` defaults to 32768; plus
  `setContextSize(_:)` for the app's `static let`, which has no settings at
  type-init (D3).
- New state under the existing `lock` (`:83`):
  `private var continuations: [String: (path: String, nextLine: Int, bare: Bool)]`.
- `readResult`, the non-`readCache` path: parse `start_line` / `max_lines` /
  `whole` / `raw` from `request.params`; resolve and read as today; call
  `ReadWindow.render`; then under the lock, set or clear
  `continuations[workspaceRoot]` from `nextLine` (D4).
- `more`: look up `continuations[workspaceRoot]`; nil → `ToolExecutionResult(ok:
  false, text: "error: no previous output to continue")`. Otherwise render from
  `nextLine` with `count` (default: the tier) and the recorded `bare`, and
  update the entry.
- `resetReadState()` — clears `continuations`; called from the session
  start/restart block (`AgentController.swift:359-384`).
- The `readCache` branch (`:161-181`) is byte-for-byte unchanged (D7).

### 3. `Sources/SwiftStar/AgentController.swift` (extend)

- In the session start/restart block, alongside the existing `outcomeBuilder`
  (`:380`) and `poolState` (`:384`) resets, call both
  `Self.hostToolExecutor.setContextSize(settings.contextSize)` and
  `Self.hostToolExecutor.resetReadState()`. The static executor cannot be
  constructed with settings (D3), so this block is the only place the app's
  context size can reach it — and it is the correct place, since a restart is
  exactly when a changed context size takes effect.

### 4. `Sources/SwiftStarAppKit/PoolOrchestrator.swift` (one argument)

This is not a second executor implementation. `HostToolExecutor` lives once and
is shared with `AgentController` (the P22 item-4 cleanup, recorded at `:14-19`);
`PoolOrchestrator` holds a single `hostToolExecutor` field and reassigns it per
phase, because a fresh instance *is* the per-phase reset of the `.pool` read
cache and vetted-commands allowlist. Three construction sites, one class, two
policies: `:19`/`:80` give worker phases `.pool(vettedCommands:)`, `:208` gives
the orchestrator role `.app` (the agent's own role — full bash, not a worker's
allowlist). It is consumed by the `swiftstar-agenttest` binary
(`Package.swift:49`), not by the app.

What this cycle owes it is one argument — `contextSize` at each site (D3) — and
one warning. Windowing **changes what the orchestrator's reads return**, and the
fourth campaign arm is still unrun (`ROADMAP.md:15`). The arms must not straddle
this cycle: finish the outstanding arm first, or re-baseline all four. The
superseded plan's construction-site audit (`grep -rn "Policy("`) missed this
site and would have changed the instrument silently — the fourth such near-miss
the ROADMAP records.

**This also bounds D5.** Because `PoolOrchestrator` gets a fresh instance per
phase, its continuation map dies with the instance and needs no reset.
`resetReadState()` exists solely for the app's process-lifetime
`static let` (`AgentController.swift:838`), which is the only executor that
outlives a session.

No turn counter, no ordinal, no model-facing number that the model has no way to
interpret — the superseded spec's D5 has no successor here.

## Cycles

| # | Cycle | Gate | Risk |
|---|---|---|---|
| **1** | `ReadWindow` pure type + fast-tier tests (window arithmetic, both header shapes, byte budget, raw mode, EOF, over-long line, invariant) | fast tier green, **red first** | none |
| **2** | `HostToolExecutor` wiring: param parsing, `contextSize`, continuation map, `more`, `resetReadState` | integration tests green; `readCache` path untouched | low |
| **3** | `AgentController`: `contextSize` at construction, reset on restart | build + suite green | none |
| **4** | **Measurement**: a live read-heavy session of the 1809 shape; `swiftstar-analyze rereads` on it; the window-distribution check (D9); paired-bill `diff` recorded as secondary | note committed with the pre-registered falsifier answered either way | the phase's one live step |

## Tests (fast tier, no model, no subprocess)

1. **Window arithmetic** — `start_line` clamps below 1; `start_line` past EOF
   yields an empty body and an EOF header; `max_lines` past EOF clamps;
   `whole: true` reaches EOF when it fits.
2. **Header shapes** — truncated renders `lines A-B of N; continue_offset=C;
   call more with count=K…`; EOF renders `lines A-B of N` with no
   `continue_offset`. Both matched against the engine's format strings
   (`ds4_agent.c:8148-8154`).
3. **The D2 invariant** — for a file whose default-tier window exceeds the
   budget: the result is ≤ `byteBudget`, and the header's `A-B` equals the
   first and last line numbers present in the body. The refusal-adjacent case
   (budget cuts before `max_lines`) has its sibling success (budget does not
   bind, full `max_lines` served) per rule 3.
4. **`condense` is a no-op** — `ToolResultCondenser.condense(result.text) ==
   result.text` for a rendered window. This is the test that would have caught
   the superseded spec's error; it pins the whole design.
5. **Raw mode** — bare bytes plus the `[Read truncated at line X of N…]` note;
   no line-number prefixes.
6. **Over-long single line** (D6) — a line exceeding the budget is emitted,
   truncated with `[line N truncated at M of K bytes]`, `nextLine == N+1`, and
   the result is still ≤ budget.
7. **Line prefix** — `"%d "`, 1-based, matching `ds4_agent.c:8160-8163`.

## Integration tier (real files, fake engine — seconds)

8. **`more` continues** — `read` a file larger than the budget, then `more`;
   the second result starts at the first result's `continue_offset` and no line
   is skipped or repeated across the seam.
9. **EOF clears the continuation** (D4) — read a small file whole, then `more`
   → `"error: no previous output to continue"`. Sibling success: read a large
   file, then `more` → content.
10. **Continuations are keyed per workspace root** (D5) — two workspaces, one
    executor; a truncated read in A, then a truncated read in B, then `more` in
    A continues **A's** file. A single-scalar implementation fails this.
11. **Confinement unchanged** — an out-of-grant path still refuses with the
    existing message; the pool `readCache` tests still pass byte-identically.
12. **`resetReadState`** — read, reset, `more` → the no-continuation error.

## Live validation (closure evidence)

A scripted read-heavy session on the real engine, the 1809 shape: explore this
repo, work on a file over 8000 bytes, force a compaction. Then:

- **The pre-registered falsifier (D9).** Extract the read sequence with
  `swiftstar-analyze rereads` and inspect the window distribution.
  **If the capture still shows many distinct windows clustered on one region of
  one file, windowing did not fix the loop and this cycle failed** — recorded as
  such, not re-explained.
- **Secondary:** `swiftstar-analyze diff` against `live/20260827-200648`. The
  Σsuffix ratio is recorded whatever it is; a rise is acceptable if the turn
  completed, a fall is not by itself evidence (rule 5).
- **The 1809 counterfactual:** `AgentView.swift`'s `bottomStatusBar` sits near
  line 252 of 427. A single `read` with `start_line: 252` must now return it.

## Out of scope

The read guard and the pool `readCache` honesty fix (both → P24.2, decided
together); the `more` consent default (`path` → `"."`); `recall` and the
deterministic compaction skeleton (both "sequence after P24"); window-honoring
in the engine's own non-host-tools path (already correct there).

## Note on status

Stamped `proposed` until the cycle ships, then `implemented`.

## Documents this spec invalidates

Correct these when the cycle lands, or they will re-teach the error:

1. [`2026-08-30-p24-1-read-guard-design.md`](2026-08-30-p24-1-read-guard-design.md)
   — stamp `superseded`, pointing here.
2. [`2026-08-30-p24-1-read-guard.md`](../plans/2026-08-30-p24-1-read-guard.md)
   — the implementation plan for the withdrawn design; supersede with this
   spec's plan.
3. [`2026-08-30-p24-1-read-guard-before-measurement.md`](../research/2026-08-30-p24-1-read-guard-before-measurement.md)
   — its "55 redundant re-reads" framing counts the starvation loop's repeats as
   redundancy. Its "Two facts" §2 was right and is this spec's premise; §1 needs
   a correction note.
4. `Sources/swiftstar-analyze/main.swift:227-230` — the `rereads` verb's doc
   comment asserts the guard "can only short-circuit a re-read of the *same*
   window", which describes a tool that was never built.
5. The **P24 row** in [`ROADMAP.md`](../../../ROADMAP.md) — its tool list names
   "the `read`-guard (`don't-re-read`)" as P24's direct fix for the 1809 tax.
   Window-honoring takes that slot; the guard moves to P24.2.
