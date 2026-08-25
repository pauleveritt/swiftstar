# SwiftStar design: host-controlled action mode (text contract)

**Date:** 2026-08-25
**Status:** draft (brainstormed; three GLM 5.2 reviews folded in — output contract, data flow, error handling/testing/success)
**Phase:** host-controlled action mode — the next phase after P13 (number TBD). Builds on the P9 tool-callback wire and P10 isolation; addresses Mellum-class models.

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

**In:** a pinned text-output contract (the model emits labeled file blocks, the
host harvests); a rewrite of `ThinkHarvest` to match that contract fail-closed;
mutation injection so a harvested turn can become a candidate; a text-contract
repair path; the step-0 forcing-gate experiment; the two host-verified
experiments (build + repair).

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
- **`RepairLoop` assumes agentic edit/write tool calls.** `RepairLoop.run`
  (`RepairLoop.swift:125-127`) does `runPhase` → `runValidation` →
  `WorktreeDispatcher.finalize` (not `finalizePhase`); a `.receipt` maps
  straight to `.exhausted`. Text-contract repair is a *change* to `RepairLoop`
  (the same harvest+mutation-injection seam at `finalize`'s call site), not a
  reuse.
- **The existing noChanges branch grades the accumulated tree.**
  `main.swift:557`: `noChanges + eos → continue` grades the tree. It must be
  gated on `harvestStepRan == false`, or a harvest-that-found-nothing would
  silently grade an unbuilt tree.
- **`ThinkHarvest` today is last-writer-wins + proximity + substring.**
  `labelWindow = 400` (`ThinkHarvest.swift:23`), fence regex
  ` ```[a-zA-Z]*\n ` (drops `jinja2`/`html5`), `isWholePath` substring
  (`:74`), "last mention wins" (`:50`). C10 found the suffix/digit-tag/
  last-block-wins bugs. The contract below is a **rewrite**, not a reuse;
  `ThinkHarvestTests.harvestsBlockLabelledByPrecedingProse` (prose-only
  labeling) is incompatible and must be inverted/deleted.
- **Mellum stops at `eos`** in the current harness (P13 benchmark: 348/899/1
  tokens, `stop_reason: eos`). C9's `.limit` captures were Laguna-with-thinking;
  `.limit`/`.contextFull` remain session-exhaustion in `runOnce` and must not
  become a harvest trigger.
- **The wire does not carry a text-contract distinction**; `HandoffPacket` has
  a custom `init(from:)` (new fields need `decodeIfPresent` or old captures
  break) and `HandoffPacketValidator` is the up-front gate (not
  `PhasePacketBuilder`).

## Design

### Section 1 — the output contract (pinned)

The model is never asked to initiate a tool call. The packet's writable
contract becomes:

> *"Do not call tools. For each file, emit a heading line `### \`<path>\`` (path
> relative to the workspace root), immediately followed by one fenced code block
> containing the complete file contents. A fenced block with no preceding
> heading is ignored."*

**Matching (fail-closed):**

- A heading is accepted **only** if its *normalized* path exactly equals an
  entry in `writableFiles` (normalize: strip leading `./`, collapse interior
  `./`/`//`, reject trailing `/`).
- "Immediately followed by" is a **grammar**, not a heuristic: heading line →
  optional single blank line → fence opener. A heading with no fence before the
  next heading is dropped, never carried forward.
- A fence with no preceding *accepted* heading → ignored.
- An unterminated fence → ignored.
- The fence info-string is matched **permissively** (any non-newline run) only
  to locate the body, never parsed for attribution.
- **Fence parity**: a `### \`path\``-looking line inside a fenced body does not
  flip attribution (only headings *outside* fences count).
- Multiple emissions of one file: **first complete labeled block wins** (the
  re-review tail cannot overwrite an earlier good draft).
- An **unexpected tool call during a harvest turn → abort the harvest**
  (contract broken); the turn is treated as agentic, no harvest.
- A well-formed heading naming a path **outside** `writableFiles` → **abort the
  harvest** (contract/harvest defect), never silently dropped.

**Trigger:** a turn with **0 tool calls** ending `noChanges + eos`.

### Section 2 — data flow

**Build (text-contract), per phase:**

1. `phasePacket` attaches the text-contract directive (new `HandoffPacket`
   field `textContract: Bool`, default false, `decodeIfPresent`) instead of the
   "use your write tool" note. `HandoffPacketValidator` gains the rule:
   `textContract ⇒ writableFiles` non-empty.
2. Dispatch to the pool unchanged. Turn outcomes branch: **≥1 tool call →
   agentic turn, no harvest** (any labeled blocks in its text are ignored).
   **0 tool calls + `noChanges` + `eos` → harvest fires.**
3. **Harvest is a new step in `runOnce` between `orch.runPhase` and
   `WorktreeDispatcher.runValidation`:** parse labeled blocks (Section 1 rules),
   write matched files into the worktree (bounded by `writableFiles`), **then
   inject the harvested paths into `outcome.mutations` (relativized, matching
   `writableFiles`) before finalization** — without this the verdict always
   returns `.noChanges`.
4. Run `validationCommand` → `finalizePhase` (candidate or receipt). The
   existing `noChanges+eos → grade accumulated tree` branch is gated on
   `harvestStepRan == false`; if harvest ran and found **0 blocks**, the turn is
   an **initiation-failure receipt that stops the transaction**, not a continue.

**Repair (text-contract):** a **change to `RepairLoop`** — insert the same
harvest + mutation-injection seam between its `runPhase` and `runValidation`,
feeding the mutated `TurnOutcome` into `WorktreeDispatcher.finalize` (not
`finalizePhase`). `MachineEvidence` (verbatim traceback + file contents) rides
in the packet as today; the model returns the corrected file as a labeled
block; host writes → re-grade.

**Step-0 forcing gate (experiment, not a success criterion):** a per-turn
re-prompt loop in `runOnce` (after `orch.runPhase`, before `runValidation`): on
`outcome.toolCalls.isEmpty && retriesLeft > 0`, build a forcing packet (reusing
`writableFiles`/`validationCommand`) and re-run on the **same `WorkerId` and
prepared worktree**, bounded 2. Cheap: touches none of verdict/dispatcher/txn/
`RepairLoop`/packet schema. Its output is a recorded 0→N measurement that
settles whether (b) is a live arm.

**Shared host core (reused):** `vettedCommands` (import + pytest),
`AcceptanceGrader` (13 tests), `MachineEvidence`, `WorktreeDispatcher`,
`WorktreeTransaction`.

### Section 3 — error handling, testing, success criteria

**Error handling (fail-closed, named):**

- Harvest applies the Section 1 rules. **Harvest ran and returned 0 blocks →
  `.noChanges` receipt that stops the transaction** (initiation failure); the
  continue-branch gate is `harvestStepRan == false`, evaluated before the
  `noChanges+eos` test.
- Harvested tree fails `validationCommand` → `.validationFailed` (no
  candidate) — existing behavior, applied to a harvested tree.
- Tool call during a text turn → agentic, no harvest (deterministic).
- **Failure classification (measurement backbone), made decidable:** a block
  whose heading/fence does not match the Section 1 grammar exactly is a
  **content** defect (model narration failure). A **harvest-parse defect** is
  "harvester returned 0 blocks *and* a host re-scan against the grammar finds
  ≥1 well-formed block." A disallowed-heading abort is a harvest/contract
  defect. The build bar requires failures to land in the *content* bucket, not
  harvest.

**Testing:**

- *Unit (fast tier, no model):* the `ThinkHarvest` v2 rules, enumerated —
  first-complete-block-wins, heading grammar (not prose-window), fence parity,
  allowlist-exact match, abort-on-unexpected-tool-call, abort-on-disallowed-heading,
  unterminated-fence-drop, digit-tag fence acceptance; mutation injection (text
  outcome + injected paths → verdict `.candidate`, not `.noChanges`);
  `HandoffPacket.textContract` decode (present/absent, backward-compat);
  `HandoffPacketValidator` `textContract ⇒ writableFiles` rule.
- *Integration (fake tier):* the `runOnce` harvest hook via `FakeAgentSource`
  emitting labeled blocks → candidate → graded.
- *Live (acceptance):* the build + repair experiments.

**Success criteria (exit bar = c):**

- **Build:** a host-verified candidate — imports clean, harvested set ==
  narrated set (both defined as "well-formed Section 1 headings ∩
  `writableFiles`"), failures bucketed *content* (harness-addressable), not
  harvest/parse/write.
- **Repair:** a host-verified fix — a real failure, host writes + re-runs → the
  failing test passes.
- **Hygiene:** every text-contract result is labeled "drafting quality +
  host orchestration, not agency." (The step-0 gate is an experiment; its
  recorded measurement is evidence, not a pass/fail criterion.)

## Decisions

- **D1** — Approach A: directive-in-loop. The model stays in the agent loop;
  tools stay wired; the directive says "do not call tools, emit labeled blocks."
- **D2** — the output contract is pinned as a packet directive (`textContract:
  Bool` + a constant directive text), validated by `HandoffPacketValidator`.
- **D3** — harvest is first-complete-block-wins, fail-closed, grammar-matched
  (not proximity), with fence parity and disallowed-heading/tool-call aborts.
- **D4** — mutation injection is the load-bearing step: harvested paths are
  relativized into `outcome.mutations` before finalization, or no candidate is
  ever produced.
- **D5** — the harvest trigger is `noChanges + eos` only; `.limit`/`.contextFull`
  stay session-exhaustion.
- **D6** — text-contract repair is a change to `RepairLoop` at
  `WorktreeDispatcher.finalize`'s call site, not a reuse or a new loop.
- **D7** — exit bar: build + repair each host-verified once; "host-verified" =
  imports-clean + file-set completeness + content-bucket failures (build), and a
  real failing test that passes after host re-run (repair). 13/13 is repair's
  end-to-end chase, not this phase's bar.
- **D8** — measurement hygiene: text-contract results are labeled "drafting +
  orchestration, not agency"; the step-0 forcing gate is an experiment, its
  output a recorded measurement.

## Verification (done-when)

1. `ThinkHarvest` v2 passes the enumerated fail-closed unit tests; a text-only
   outcome + injected paths produces `.candidate` (not `.noChanges`).
2. `HandoffPacket.textContract` decodes with and without the field (old captures
   intact); `HandoffPacketValidator` enforces `textContract ⇒ writableFiles`.
3. The `runOnce` harvest hook (fake tier) turns labeled-block output into a
   graded candidate; harvest-with-0-blocks stops the transaction, never
   continues.
4. The build experiment: Mellum, through the text contract, yields a
   host-verified candidate (imports clean, file-set complete, failures bucketed
   content).
5. The repair experiment: Mellum, through the text contract, fixes a real
   failure host-verified (host writes + re-runs → test passes).
6. The step-0 forcing gate produces a recorded 0→N measurement.
7. Full test suite green; every text-contract capture carries the
   "drafting + orchestration, not agency" label.

## Deferred

- Promoting the directive to a first-class packet `mode` enum (`agentic |
  textContract`) once text mode proves out (the "promote A to C" step).
- A tool-free engine mode; sampler/`</think>` engine work.
- The steering profile (still P13-deferred).
- Any per-model pass-rate guarantee.
