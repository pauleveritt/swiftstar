# SwiftStar design: host-controlled action mode (text contract)

**Date:** 2026-08-25
**Status:** draft (brainstormed; three GLM 5.2 reviews folded in, then a Claude +
Fable review pass — source-verified, scope trimmed)
**Phase:** **P15 — Host-controlled action mode.** A phase of its own, not a P12
sub-phase: P12's direction is *making agency reliable*, and this phase
deliberately removes agency from the build path. Builds on the P9 tool-callback
wire and P10 isolation; addresses Mellum-class models. (P14 is the docs site.)

## Problem

Mellum 2.1 (and plausibly small-MoE models generally) is fluent at producing
text that has the *shape* of correct, grounded, complete work, without a
reliable internal signal distinguishing "I described doing this" from "I did
this." Measured failure modes: (1) narration instead of tool calls — 0 calls
across path-presentation × nudge × seed at the published sampler (P13 benchmark);
(2) fabricated validation ("tests passed" when nothing ran); (3) byte-identical
re-emission of wrong code even when shown the exact error. The one thing that
produced host-verified correct code was *host-controlled text mode*: the host
runs the test, selects the file, hands the model the file + traceback, and the
model returns corrected text the host validates and writes.

The failure sits on the **"should I act" axis**, not the content axis. This
phase separates the two: the model produces *content* (its strength), the host
owns *execution and verification* (deterministic). The exit goal is a verdict —
**confidence that Mellum is ready to improve (harness-addressable), not
fundamentally broken (content-broken)** — not a product.

## Scope (strict)

**In:** a text-output contract (the model emits labeled file blocks, the host
harvests); a new block parser, fail-closed, replacing the unwired `ThinkHarvest`;
mutation injection so a harvested turn can become a candidate; a text-contract
repair path; the step-0 forcing-gate experiment; the two host-verified
experiments (repair first, then build).

**Out:** any engine work (no `</think>` injection, no sampler changes); a
tool-free engine mode (the model stays in the agent loop — Approach A);
changing `AcceptanceGrader`, `MachineEvidence`, `WorktreeDispatcher`,
`WorktreeTransaction` beyond the harvest seam; a pass-rate guarantee (13/13 is
the end-to-end quality gate repair chases, not this phase's bar); the steering
profile (still P13-deferred).

## Gardenable facts (verified against source)

- **A candidate requires non-empty `mutations`, which only tool calls produce.**
  `WorktreeDispatch.verdict` step 4 (`WorktreeDispatch.swift:82`):
  `if allowedMutations.isEmpty { return .receipt(.noChanges) }`. A text-only
  turn has empty mutations, so the host can write files and the verdict still
  returns `.noChanges`. **The harvest must inject harvested paths into
  `outcome.mutations` (relativized, matching `writableFiles`) before
  finalization.**
- **The budget check runs *before* the mutations check.** `verdict` step 2
  (`WorktreeDispatch.swift:73-75`) returns `.budgetExceeded` on
  `generatedTokens > packet.turnBudget` ahead of every later branch. Text mode
  emits complete file bodies as *response* tokens — strictly heavier than the
  tool-call path — so a harvested, injected, validation-passing turn can still
  die as `.budgetExceeded`. Text-contract packets need their own `turnBudget`
  policy.
- **`RepairLoop` assumes agentic edit/write tool calls.** `RepairLoop.run`
  (`RepairLoop.swift:123-127`) does `runPhase` → `runValidation` →
  `WorktreeDispatcher.finalize` (not `finalizePhase`); a `.receipt` maps
  straight to `.exhausted`. Text-contract repair is a *change* to `RepairLoop`
  (the same harvest+mutation-injection seam at `finalize`'s call site), not a
  reuse.
- **Repair evidence is capped, not verbatim.** `RepairLoop.run` defaults
  `fileCap: 16384` and `outputCap: 8192` (`RepairLoop.swift:50`), applied via
  `MachineEvidence.cappedContent` / `cappedFailureOutput` (`:78`, `:94`). Under
  the agentic path a truncated view is merely lossy context. Under a contract
  demanding a **complete** re-emission, a file shown truncated is re-emitted
  truncated and the host overwrites a good copy with a short one. Repair needs a
  cap-aware guard (see Section 3).
- **The existing noChanges branch grades the accumulated tree.**
  `main.swift:557` (`Sources/swiftstar-agenttest/main.swift`): `noChanges + eos
  → continue` grades the tree. A harvest that found nothing must not reach it —
  handled by a **distinct receipt case**, not by a flag beside `.noChanges`.
- **`ThinkHarvest` is unwired dead code.** Its only references are its own test
  file; no production call site exists. It was written for a *different*
  mechanism — Laguna's think-stream, proximity labeling (`labelWindow = 400`,
  `ThinkHarvest.swift:23`), `.limit`-truncation defense, last-writer-wins
  (`:50`), substring `isWholePath` (`:74`). This phase writes a **new
  `LabeledBlockParser`** over final assistant text and **deletes `ThinkHarvest`
  and `ThinkHarvestTests` outright**. There is no rewrite risk and no test to
  invert.
- **`HandoffPacketValidator` already covers the proposed new rule.** It rejects
  empty `writableFiles` unconditionally (`HandoffPacketValidator.swift:58`), so
  `textContract ⇒ writableFiles` non-empty adds nothing. It also requires
  `toolCallBudget > 0` (`:62`) — a text-contract packet must still carry a
  nonzero tool budget it never intends to spend.
- **Mellum stops at `eos`** in the current harness (P13 benchmark: 348/899/1
  tokens, `stop_reason: eos`). C9's `.limit` captures were Laguna-with-thinking;
  `.limit`/`.contextFull` remain session-exhaustion in `runOnce` and must not
  become a harvest trigger.
- **The wire does not carry a text-contract distinction**; `HandoffPacket` has
  a custom `init(from:)` (new fields need `decodeIfPresent` or old captures
  break) and `HandoffPacketValidator` is the up-front gate (not
  `PhasePacketBuilder`).

## Design

### Section 0 — the forcing gate runs first (gating, not a footnote)

A per-turn re-prompt loop in `runOnce` (after `orch.runPhase`, before
`runValidation`): on `outcome.toolCalls.isEmpty && retriesLeft > 0`, build a
forcing packet (reusing `writableFiles`/`validationCommand`) and re-run on the
**same `WorkerId` and prepared worktree**, bounded 2. It touches none of
verdict/dispatcher/txn/`RepairLoop`/packet schema.

**This is task 1, and its result gates the rest of the phase.** If a bounded
forcing re-prompt moves Mellum 0→N tool calls, the text contract is not needed
for the *build* case at all and Section 2's build path shrinks or disappears.
Its output is a recorded 0→N measurement, not a pass/fail criterion — but the
plan reads it before building Section 1 out.

### Section 1 — the output contract

The model is never asked to initiate a tool call. The packet's writable
contract becomes:

> *"Do not call tools. For each file, emit a heading line `### \`<path>\`` (path
> relative to the workspace root), immediately followed by one fenced code block
> containing the complete file contents. A fenced block with no preceding
> heading is ignored."*

**Matching (fail-closed) — the minimal pinned set:**

- A heading is accepted **only** if its *normalized* path exactly equals an
  entry in `writableFiles` (normalize: strip leading `./`, collapse interior
  `./`/`//`, reject trailing `/`).
- "Immediately followed by" is a **grammar**, not a heuristic: heading line →
  optional single blank line → fence opener. A heading with no fence before the
  next heading is dropped, never carried forward.
- A fence with no preceding *accepted* heading → ignored.
- An unterminated fence → ignored (never write a truncated body over a good one).
- The fence info-string is matched **permissively** (any non-newline run) only
  to locate the body, never parsed for attribution. This admits `jinja2`,
  `html5`, and digit-tagged fences that the old regex dropped.
- **Fence parity**: a `### \`path\``-looking line inside a fenced body does not
  flip attribution (only headings *outside* fences count).
- A well-formed heading naming a path **outside** `writableFiles` → the block is
  **dropped and recorded** in its own classification bucket (`out-of-grant
  heading`). It does **not** abort the turn: aborting would let one stray
  `README.md` heading destroy four correct files, and the verdict's step-1
  revision check already refuses out-of-grant paths a second time after
  injection.
- Multiple emissions of one file: take the **first complete labeled block** and
  **log the duplicate count**. First-vs-last is an unmeasured guess — the old
  harvester chose last ("later drafts refine earlier"), this chooses first ("the
  re-review tail cannot overwrite a good draft"). Neither is evidence-backed yet;
  the counter is what makes the live captures settle it.

**Deliberately not pinned yet — measured 2026-08-25.** The heading form is now
settled by measurement, not prediction: Mellum's *build* turns emit **`#<path>`**
headings (single hash, no space, no backticks) immediately before fenced blocks
(evidence: P13 captures `20260825-120531-roadmap` — `#app.py`,
`#templates/base.html`, `#tests/test_app.py`). The parser therefore accepts
**both** `#<path>` (one-or-more `#`, optional whitespace, bare path to end of
line — matched by the project's own regex, *not* a Markdown ATX parse, since
`#app.py` without a space is not a valid CommonMark heading) **and** the earlier
`### \`<path>\`` backtick form. Exact allowlist match stays the only attribution
gate — `#` is now a common prose/comment character, so no normalization slack is
added to catch near-misses. **Fence parity is now structural, not defensive:**
`#app.py` is a Python comment, so a heading-looking line inside a fenced body
must never flip attribution; this is tested explicitly. The repair arm's failure
(no block at all, correct prose diagnosis) is a *separate* finding from the
build arm's `#<path>` emission and is tracked as such.

**Rule deleted from the earlier draft:** *"an unexpected tool call during a
harvest turn → abort the harvest."* It is unreachable. Harvest runs post-turn on
a completed `TurnOutcome`, and Section 2 step 2 routes any turn with ≥1 tool
call to the agentic path before harvest starts. There is no moment at which a
tool call can arrive "during" a harvest; the rule described a streaming
harvester this design does not have.

**Trigger:** computed from the `TurnOutcome` at the hook point —
`outcome.toolCalls.isEmpty && outcome.stopReason == .eos`. It is **not**
`noChanges`: `.noChanges` is a *verdict* from `finalizePhase`
(`WorktreeDispatch.verdict` step 4), produced two steps downstream of the
harvest hook and downstream of harvest's own mutation injection. The earlier
draft's `noChanges + eos` trigger referenced a value that does not exist yet
when harvest must decide.

### Section 2 — data flow

**Repair (text-contract) — built and run first.** The strongest existing
evidence is that host-controlled text mode already produced host-verified
correct code in *repair*. It is one file, one block, one insert, and it needs
only a subset of Section 1. It is therefore the first live experiment.

A **change to `RepairLoop`**: insert the harvest + mutation-injection seam
between its `runPhase` and `runValidation`, feeding the mutated `TurnOutcome`
into `WorktreeDispatcher.finalize` (not `finalizePhase`). `MachineEvidence`
(traceback + file contents) rides in the packet as today, **subject to the
`fileCap` guard in Section 3**; the model returns the corrected file as a
labeled block; host writes → re-grade.

**Build (text-contract), per phase — second, and only if Section 0 says it is
still needed:**

1. `phasePacket` attaches the text-contract directive (new `HandoffPacket` field
   `textContract: Bool`, default false, `decodeIfPresent`) instead of the "use
   your write tool" note. The field exists so captures are self-labeling. **No
   new `HandoffPacketValidator` rule** — the validator already rejects empty
   `writableFiles`. The packet still carries a nonzero `toolCallBudget` it does
   not intend to spend, and a `turnBudget` raised for whole-file emission.
2. Dispatch to the pool unchanged. Turn outcomes branch: **≥1 tool call →
   agentic turn, no harvest** (any labeled blocks in its text are ignored).
   **0 tool calls + `eos` → harvest fires.**
3. **Harvest is a new step in `runOnce` between `orch.runPhase` and
   `WorktreeDispatcher.runValidation`:** parse labeled blocks (Section 1 rules),
   write matched files into the worktree (bounded by `writableFiles`), **then
   inject the harvested paths into `outcome.mutations` (relativized, matching
   `writableFiles`) before finalization** — without this the verdict always
   returns `.noChanges`. Injected paths pass **through** the verdict's step-1
   revision check, not around it: that re-check is a deliberate second gate on
   the grant.
4. Run `validationCommand` → `finalizePhase` (candidate or receipt). A harvest
   that ran and found **0 blocks** emits a **distinct receipt case**
   (`.contractNotFollowed`) that stops the transaction. It is not `.noChanges`
   with a flag beside it: `main.swift:557` already gives `.noChanges + eos` the
   opposite meaning ("continue and grade"), and overloading one case with an
   out-of-band boolean puts the meaning somewhere the type cannot carry it. A
   distinct case removes the gate entirely and shows up correctly in the
   existing receipt switches (`AgentController.swift:563`,
   `DispatchView.swift:149`).

**Shared host core (reused):** `vettedCommands` (import + pytest),
`AcceptanceGrader` (13 tests), `MachineEvidence`, `WorktreeDispatcher`,
`WorktreeTransaction`.

### Section 3 — error handling, testing, success criteria

**Error handling (fail-closed, named):**

- Harvest applies the Section 1 rules.
- **Harvest ran and returned 0 blocks → `.contractNotFollowed` receipt that
  stops the transaction** (initiation failure).
- Harvested tree fails `validationCommand` → `.validationFailed` (no candidate)
  — existing behavior, applied to a harvested tree.
- Tool call on the turn → agentic path, no harvest (deterministic, decided
  before harvest runs).
- **Cap guard (repair):** before a text-contract repair packet is built, any
  writable file whose contents exceed `fileCap` is a **hard precondition
  failure**, not a silent truncation. A model asked to re-emit a complete file
  it was shown truncated will return a truncated file and the host will write
  it. Either raise the cap for text-contract repair or refuse the round with a
  named receipt; the plan picks one and records why.
- **Budget:** text-contract packets set `turnBudget` from expected total file
  bytes, not from the agentic default, because `verdict` step 2 fires ahead of
  everything else.
- **Failure classification (measurement backbone), made decidable:** a block
  whose heading/fence does not match the Section 1 grammar exactly is a
  **content** defect (model narration failure). A **harvest-parse defect** is
  "harvester returned 0 blocks *and* a host re-scan against the grammar finds
  ≥1 well-formed block." An out-of-grant heading is its own bucket. The build
  bar requires failures to land in the *content* bucket, not harvest.

**Testing:**

- *Unit (fast tier, no model):* `LabeledBlockParser` rules, enumerated —
  first-complete-block-wins + duplicate counter, heading grammar (not
  prose-window), fence parity, allowlist-exact match, out-of-grant heading
  dropped-and-recorded (turn survives), unterminated-fence drop, permissive
  info-string (`jinja2`, `html5`, digit tags); mutation injection (text outcome
  + injected paths → verdict `.candidate`, not `.noChanges`); injected
  out-of-grant path still refused by verdict step 1;
  `HandoffPacket.textContract` decode (present/absent, backward-compat).
- *Integration (fake tier):* the `runOnce` harvest hook via `FakeAgentSource`
  emitting labeled blocks → candidate → graded; harvest-with-0-blocks →
  `.contractNotFollowed` → transaction stops.
- *Live (acceptance):* the repair experiment, then the build experiment.
- *Deleted:* `ThinkHarvest` and `ThinkHarvestTests` (unwired, different
  mechanism).

**Success criteria (exit bar = c):**

- **Repair (first):** a host-verified fix — a real failure, host writes +
  re-runs → the failing test passes.
- **Build (second):** a host-verified candidate — imports clean, **the phase's
  required file set ⊆ the harvested set**, failures bucketed *content*
  (harness-addressable), not harvest/parse/write. (The earlier
  "harvested set == narrated set" criterion was circular: both sides were
  defined as "well-formed Section 1 headings ∩ `writableFiles`", so it held by
  construction and tested nothing.)
- **Hygiene:** every text-contract result is labeled "drafting quality +
  host orchestration, not agency." (The step-0 gate is an experiment; its
  recorded measurement is evidence, not a pass/fail criterion.)

## Decisions

- **D1** — Approach A: directive-in-loop. The model stays in the agent loop;
  tools stay wired; the directive says "do not call tools, emit labeled blocks."
- **D2** — the output contract is a packet directive (`textContract: Bool` + a
  constant directive text). No new validator rule; the existing
  empty-`writableFiles` rejection already covers it.
- **D3** — the parser is a **new `LabeledBlockParser`**; `ThinkHarvest` and its
  tests are deleted, not rewritten. Fail-closed, grammar-matched (not
  proximity), fence parity, out-of-grant headings dropped-and-recorded.
- **D4** — mutation injection is the load-bearing step: harvested paths are
  relativized into `outcome.mutations` before finalization, passing **through**
  the verdict's step-1 revision check, or no candidate is ever produced.
- **D5** — the harvest trigger is `toolCalls.isEmpty && stopReason == .eos`,
  computed from the `TurnOutcome` at the hook point; `.noChanges` is a
  downstream verdict and cannot be the trigger. `.limit`/`.contextFull` stay
  session-exhaustion.
- **D6** — text-contract repair is a change to `RepairLoop` at
  `WorktreeDispatcher.finalize`'s call site, not a reuse or a new loop — and it
  ships **before** the build path.
- **D7** — a harvest that finds nothing emits a **distinct** receipt case
  (`.contractNotFollowed`), never `.noChanges` plus a flag.
- **D8** — exit bar: repair + build each host-verified once; "host-verified" =
  a real failing test that passes after host re-run (repair), and imports-clean
  + required-file-set coverage + content-bucket failures (build). 13/13 is
  repair's end-to-end chase, not this phase's bar.
- **D9** — the step-0 forcing gate is **task 1** and gates how much of the build
  path gets built; its output is a recorded measurement.
- **D10** — text-contract packets carry their own `turnBudget` (whole-file
  emission is token-heavy and `verdict` step 2 fires first), and text-contract
  repair carries a `fileCap` precondition rather than silently shipping
  truncated evidence into a complete-file contract.
- **D11** — measurement hygiene: text-contract results are labeled "drafting +
  orchestration, not agency."

## Verification (done-when)

1. The step-0 forcing gate produces a recorded 0→N measurement, and the plan
   records what it changed about the build path.
2. `LabeledBlockParser` passes the enumerated fail-closed unit tests; a text-only
   outcome + injected paths produces `.candidate` (not `.noChanges`); an injected
   out-of-grant path is still refused by verdict step 1. `ThinkHarvest` and its
   tests are gone.
3. `HandoffPacket.textContract` decodes with and without the field (old captures
   intact).
4. The repair experiment: Mellum, through the text contract, fixes a real
   failure host-verified (host writes + re-runs → test passes), with the
   `fileCap` precondition enforced.
5. The `runOnce` harvest hook (fake tier) turns labeled-block output into a
   graded candidate; harvest-with-0-blocks emits `.contractNotFollowed` and stops
   the transaction, never continues.
6. The build experiment: Mellum, through the text contract, yields a
   host-verified candidate (imports clean, required file set covered, failures
   bucketed content) — no `.budgetExceeded` from the whole-file token load.
7. Full test suite green; every text-contract capture carries the
   "drafting + orchestration, not agency" label.

## Deferred

- Promoting the directive to a first-class packet `mode` enum (`agentic |
  textContract`) once text mode proves out (the "promote A to C" step).
- Tightening Section 1 past the minimal pinned set — waits on real captures from
  the repair experiment.
- A tool-free engine mode; sampler/`</think>` engine work.
- The steering profile (still P13-deferred).
- Any per-model pass-rate guarantee.
