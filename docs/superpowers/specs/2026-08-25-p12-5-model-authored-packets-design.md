# SwiftStar P12.5 design: Model-authored packets (the decompose role)

**Date:** 2026-08-25
**Status:** drafted and self-approved during an autonomous overnight session (no
human review in the loop while running); reviewed by Opus before build in two
rounds (round 1 — 4 blocking findings; round 2 — re-verified the fixes and
found one still-blocking issue plus one under-specified detail, both folded
into this revision) and again before landing.
**Phase:** P12 — Reliable agency, step P12.5. This is P12's own named reopen
condition (see [`2026-08-25-p12-verdict-record.md`](../research/2026-08-25-p12-verdict-record.md)).

This spec is the authority on *how* P12.5 is done. The P12 plan
([`2026-08-24-p12-reliable-agency.md`](../plans/2026-08-24-p12-reliable-agency.md))
stub for P12.5 reads: "Decompose → schema validation (microseconds, fails
closed) → P12.4's proven chain. If decompose is bad, branch: use another model
for decompose only." **Done when:** a model-authored packet passes validation
and drives P12.4 to the same result as a hand-authored one — or the gap is
characterized.

## Problem

Every phase packet today is host-authored. The harness's `decompose(_:)`
(`Sources/swiftstar-agenttest/main.swift:115-120`) is a bare string split on
`"\n## Phase "` — no model involvement, no judgment, no packet emitted for
this step at all. `PacketRole.decompose` has existed since P10/P11
(`Sources/SwiftStarKit/HandoffPacket.swift:33-37`) and is **never referenced
anywhere except its own case declaration** — confirmed by a repo-wide grep.
It is a reserved, unexercised enum case. P12's central structural claim — a
host-owned scaffold letting one small local model fill three roles — is
two-thirds evidenced (implement, repair) and one-third untested. This is that
third.

## Gardenable facts (verified against the source)

- **The doctrine is unchanged by this phase.** "Host owns phase boundaries,
  budgets, permissions, validation, and recovery; model supplies judgment and
  code" (P12.0's charter). Model-authored packets must not mean the model
  computes `writableFiles`, budgets, or `validationCommand` — those stay
  host-computed exactly as `PhasePacketBuilder.build` already does for every
  implement/repair packet. The model's judgment is scoped to **where the phase
  boundaries fall and what each phase's task text says** — precisely what
  `decompose`'s naive split does today, done with reasoning instead of a
  string search.
- **The full chain past decompose is already proven.** `phasePacket`/
  `PhasePacketBuilder.build` (phase text → `HandoffPacket`) →
  `HandoffPacketValidator.validate` (gate) → `PoolOrchestrator.runPhase`
  (dispatch) is P12.4's chain, unchanged by this design. P12.5 only needs to
  produce phase texts a model wrote instead of a splitter — everything
  downstream is reused verbatim.
- **A validation gate already exists and is cheap.** `HandoffPacketValidator.
  validate` (`Sources/SwiftStarKit/HandoffPacketValidator.swift:31-88`) runs
  in-process, no I/O, and already rejects empty `taskText`, empty
  `writableFiles`, non-positive budgets, and a missing `validationCommand`.
  "Schema validation (microseconds, fails closed)" in the plan stub describes
  this validator exactly — it does not need to be built, only exercised
  against model output instead of split output.
- **There is a template for a model-authored, role-scoped packet.**
  `repairPacket(_:phaseScoped:)` (`main.swift:231-328`) already builds a
  `role: .repair` packet with a directive telling the model what job it's
  doing, then routes it through the same builder. `.decompose` follows the
  same shape: a directive packet, dispatched once before the phase loop,
  whose *output* (not a file mutation) is harvested and fed back into
  `decompose`'s existing phase-text shape.
- **The host must not trust prose as structure.** Per P12's own rule
  ("success is never inferred from prose"), the model's decompose output is
  not itself the contract — it is parsed by the *same* deterministic
  `"\n## Phase "` splitter the host uses today, then every resulting phase
  text still goes through the full builder + validator + dispatch chain
  unchanged. The model can only fail closed (zero phases parsed, or a later
  packet fails `HandoffPacketValidator`) — it cannot bypass validation by
  writing convincing-looking prose, because nothing downstream reads prose as
  fact.

## Opus review, round 1 — 4 blocking findings, folded in below

A pre-build Opus review of the first draft (this section records what it
found, since the findings changed the design materially, not just cosmetically):

- **The splitter fails *open*, not closed (was D2).** `decompose` splits on
  `"\n## Phase "` — the leading `\n` means a model response that opens
  directly with `## Phase 1: …` (the single most likely shape) loses phase 1
  into `preamble` silently, or yields zero phases for a single-phase reply.
  The claimed "fails closed" property was false for the most probable input.
- **`writableFiles: []` cannot pass `HandoffPacketValidator`, which the doc
  itself cited as rejecting empty `writableFiles` and blank
  `validationCommand` (was D1/D3).** The draft's own gardenable fact
  contradicted its own decision.
- **`textContract: true` does not fit a prose deliverable (was D1).** That
  flag routes through `TextContractHarvest.run`, which harvests *fenced file
  blocks keyed on `writableFiles`* — with `writableFiles: []` it harvests
  nothing. Worse, the harness exists because Mellum-class models sometimes
  reason-then-stop before emitting, which P15 already had to correct for with
  a follow-up turn; decompose needs the same protection, not a bare read.
- **n=1-vs-n=1 cannot support a pass/fail equivalence claim (was D4).** This
  project's own verdict record headlines an unchanged config swinging
  0/2 → 2/2 → 1/2 across batches. One run per arm measures variance, not
  decompose.
- Two more, non-blocking but required: dispatching before `phases` exists
  means giving up the pre-model-load validation gate for this arm (say so,
  don't pretend it still runs); and dispatching decompose on worker 1 would
  pollute the implement worker's session with the decompose turn, confounding
  the very comparison D4 wants to make.

## Opus review, round 2 — one still-blocking finding

Round 1's fix routed decompose to `WorkerId.orchestrator` (id `0`) on the
theory that it's a real, spawned, never-dispatched-to session. Verified real
and spawned (`PoolEngine.swift`: pool N = orchestrator + N-1 workers) — but
**still blocking**: `PoolOrchestrator`'s per-worker read loop matches on
`poolEvent.worker == worker`, and the engine's *startup* handshake — emitted
once, before any prompt, with no `worker` field — parses to `.orchestrator`
by the wire parser's own default-when-absent rule (`WorkerId.swift`'s doc:
"Absent on a single-session wire, so a parser defaults to `.orchestrator`").
Today that startup line is silently skipped by every dispatch because
workers 1/2 never match tag `0`. A decompose call listening on worker `0`
would match it directly and treat the boot handshake as its own turn-end,
racing (or pre-empting) the model's real reply. This is real, not
theoretical — it is the literal first line on the wire, and decompose is
literally the first `runPhase` call issued to the orchestrator in the model
arm. Round 2 also flagged the D2 fix as under-specified: prepending `"\n"`
unconditionally changes the *baseline* arm's `preamble` (existing specs
already open with a title before `"## Phase 1"`, so the prepended `\n` isn't
byte-identical to today's output) — the test-plan's own "no regression on the
baseline" bullet would fail as originally written.

**Resolution, folded into D1/D2 below:** give decompose its own worker
instead of reusing `.orchestrator` — bump the pool from 3 to 4
(`--subagent-pool 4` — one more independent KV-cache session, real per
`PoolEngine`'s own formula), dispatch decompose on `WorkerId(3)`, and leave
worker `0` exactly as untouched and unaddressed as it is today. Worker 3's
read loop matches on tag `3`; the boot handshake (tag `0`) is skipped by the
same natural mismatch that already protects workers 1 and 2 — no change to
`PoolOrchestrator`'s generic event-handling needed. For D2, only prepend the
normalizing `"\n"` when the text does not already begin with `"## Phase "` —
existing specs are untouched byte-for-byte; only the offset-0 case (a bare
model reply) gets the prepended newline.

## Decisions

- **D1 — Decompose is an extra one-shot dispatch before the phase loop, not a
  new pipeline, and it does not go through `HandoffPacketValidator`.** One
  `role: .decompose` packet, built directly (not via `PhasePacketBuilder`,
  since that requires a non-optional `validationCommand` and the validator
  downstream requires non-empty `writableFiles` — neither applies to a
  mutation-free query turn). `taskText` is a directive instructing the model
  to read the full spec and re-emit it as one or more `## Phase <N>: <title>`
  blocks, each followed by a short task description. `writableFiles: []`,
  `validationCommand: nil`. This packet is **exempt from
  `HandoffPacketValidator.validate` by construction** — no call site ever
  passes it there — because it produces no mutations and drives no acceptance
  grading directly; its own gate is D2's structural parse check, and every
  *real* packet it produces downstream still goes through the unchanged
  validator. Dispatched to **`WorkerId(3)`, a fourth pool session** — the
  pool is bumped from 3 to 4 (`--subagent-pool 4`; `PoolEngine`'s own formula
  is "orchestrator + N-1 workers," so this is one more independent KV-cache
  session, not a repurposed existing one) specifically so decompose cannot
  collide with the engine's untagged startup handshake, which parses to
  `WorkerId.orchestrator` (id `0`) by the wire parser's absent-field default
  and would otherwise be mistaken for decompose's own turn-end if decompose
  reused worker `0` (round 2 finding — see above). Worker `0` stays exactly
  as unaddressed as it is today; workers 1 (implement) and 2 (repair) are
  unaffected. Host's own `preamble` is kept as-is; only
  `phases` is replaced by the model's output — the shared spec context every
  packet gets does not become model-authored. Gated behind
  `AGENTTEST_MODEL_DECOMPOSE=1` (off by default, matching every other P12.1
  lever).

  **Ordering tradeoff, stated plainly:** decomposition now happens after the
  worker pool is up (the model has to be loaded to be asked anything), so the
  existing pre-model-load validation gate (`main.swift:338`, which validates
  every host-split phase's packet before the engine spawns) does not run for
  this arm. The per-phase gate at the dispatch loop (`main.swift:613`) is
  unchanged and still runs for every phase either arm produces — that gate,
  not the early one, is what "schema validation, fails closed" in the plan
  stub actually refers to.

- **D2 — The harvested output is parsed by the same `decompose` function used
  for host specs, moved into `SwiftStarKit` and fixed for offset-0 headings.**
  `decompose` currently lives in the executable target with no dedicated
  test and a real bug: splitting on `"\n## Phase "` silently drops phase 1
  into `preamble` (or yields zero phases) when the input opens directly with
  a heading — exactly the shape a model reply takes when it isn't preceded by
  a title line the way host spec files are. Fix: prepend a single `"\n"`
  **only when the text does not already begin with `"## Phase "`** — so an
  offset-0 model reply gets normalized while every existing host spec
  fixture (which already opens with a title line before its first heading)
  is untouched, byte-for-byte. Move the function into `SwiftStarKit` so it is
  unit-testable on its own, and add a case for heading-at-offset-0 to its
  test suite. Both arms call the identical, now-corrected function —
  the only new surface is "did the model's text parse into ≥1 phase with
  non-empty task text," not a second format to validate. If the model's raw
  text does not parse into any phase after one follow-up turn (see D3), that
  is model failure #1 and the run fails closed with a clear, distinct exit
  message — no fallback to host-split, since falling back would silently
  substitute the untested path for the tested one and defeat the point of
  measuring it.

- **D3 — One emission follow-up, mirroring P15's, before declaring failure.**
  Read `outcome.text` directly (no `textContract`, no `TextContractHarvest` —
  that path is for turning text into file writes, which decompose does not
  do). If `outcome.text` parses into zero phases via D2's function, and the
  turn's shape suggests the model reasoned without emitting (stopped at
  `.eos` with no phase headings present at all), send exactly one follow-up
  turn on the same worker session — "stop reasoning, emit the phase headings
  now, in the exact format requested" — before calling it model failure #1.
  This is the same protection P15 needed for the identical failure mode
  (reason-then-stop), scaled down to decompose's shape (no file harvest, just
  a second parse attempt).

- **D4 — Comparison, with its evidentiary limits stated up front.** A single
  `AGENTTEST_MODEL_DECOMPOSE=0` vs `=1` pair on the same spec establishes
  **structural** facts only: phase count, whether each resulting phase's
  packet passes `HandoffPacketValidator`, and whether any spec content was
  orphaned (present in the host split, absent from the model's). It does
  **not** establish pass/fail equivalence on the acceptance suite — this
  project's own verdict record shows an unchanged config swinging
  0/2 → 2/2 → 1/2 across batches, so n=1-vs-n=1 measures variance, not
  decompose. An acceptance-equivalence claim needs ≥3 runs per arm; short of
  that, the honest statement is "structurally sound, acceptance-outcome
  uncharacterized" — not a claimed match or mismatch. The model's raw
  decompose text is persisted into `captureDir` (`decompose-output.txt`,
  alongside `packet.json`) specifically so the parse is reproducible and the
  comparison isn't a number without its capture.

- **D5 — Out of scope.** The model does not choose `writableFiles`,
  `validationCommand`, budgets, or `sampling` — those remain the fixed,
  host-computed values every implement packet already gets, assigned the
  normal way once each model-authored phase text reaches
  `phasePacket`/`PhasePacketBuilder.build`. Multi-model decompose ("use
  another model for decompose only," per the plan stub's branch) is out of
  scope for this pass; if the model's decompose output characteristically
  fails, that branch is the next filed item, not something built
  speculatively now.

## Done when

- **Structural claim (the load-bearing one):** a model-authored decompose run
  produces at least one phase whose packet passes `HandoffPacketValidator`,
  and drives the run to completion (every phase dispatched, none orphaned) —
  **or**, if it does not, the gap (zero phases parsed even after the
  follow-up, which phase's packet failed validation and why) is written down
  plainly. Either outcome closes P12.5; the plan's done-when is explicitly a
  disjunction, and this is the disjunction it names.
- **Acceptance-equivalence claim (best-effort, not required to close):**
  stated only if ≥3 runs per arm were actually done; otherwise written down
  as "acceptance-outcome uncharacterized at this n," per D4. Do not report a
  single-pair pass/fail comparison as if it settled equivalence.

## Test plan

- Unit: `decompose(_:)` (moved to `SwiftStarKit`), given text that opens
  directly with `"## Phase 1: …"` (no leading title line), returns 1 phase,
  not 0 and not a dropped `preamble` — the offset-0 regression this design
  exists to fix.
- Unit: `decompose(_:)` still matches its current behavior on every existing
  host spec fixture (`fixtures/agenttest/specs/*.md`) — no regression on the
  baseline arm.
- Unit: a `role: .decompose` packet is built directly (not via
  `PhasePacketBuilder`) with `writableFiles: []`, is never passed to
  `HandoffPacketValidator.validate` anywhere in the dispatch path, and is
  dispatched on `WorkerId(3)` (pool bumped to 4), not `WorkerId(1)`/
  `WorkerId(2)`/`WorkerId.orchestrator`.
- Unit: zero-phase model output after the D3 follow-up fails closed with a
  distinct, named error (not a silent zero-phase run, not a fallback to
  host-split).
- Live: one comparison pair (`AGENTTEST_MODEL_DECOMPOSE=0` then `=1`) against
  the easy `roadmap` spec, both captures kept and cited by directory name,
  with `decompose-output.txt` persisted in the model-arm capture so the
  parse is independently reproducible. If time allows within the overnight
  budget, extend to ≥3 runs per arm before claiming acceptance equivalence;
  otherwise report the structural result only.

## Result (2026-08-25, live comparison pair)

Run against the same run of `swift build`+`swift test` (528/528 unit tests
green) that closed out implementation, then one live pair on the easy
`roadmap` spec — baseline `captures/agenttest/20260825-223848-roadmap`
(`AGENTTEST_MODEL_DECOMPOSE` unset), model arm
`captures/agenttest/20260825-224119-roadmap` (`=1`). Checked by Opus before
being written down here, same as the design and implementation were.

**Structural claim: met.** The model produced exactly 3 phase blocks in the
exact `## Phase <N>: <title>` format requested, matching the baseline's
phase count; all 3 dispatched and every packet passed
`HandoffPacketValidator` normally. No phase and no spec requirement was
orphaned — checked bullet-by-bullet against `fixtures/agenttest/specs/
roadmap.md`, not inferred from the matching count. Two Phase-1 details were
generalized rather than dropped (`templates/` directory creation, implied by
the two template files it lists; `uvicorn.run`'s `app:app`/`reload=True`
arguments, collapsed to "a `uvicorn.run` main block"), and neither is
load-bearing for acceptance. The host's `preamble` (Mission/Tech Stack) was
kept and reached every packet as designed, confirmed in
`repair-packet-1.json`.

Worth citing on its own: `decompose-output.txt` opens at byte 0 with
`"## Phase 1: Home Page"` — no title line before it. This is the D2
offset-0 case live, not hypothetical: under the pre-fix splitter this exact
model output would have swallowed phase 1 into `preamble` and yielded 2
phases, not 3. The fix earned its place in this very first live run.

**A bonus finding, stated at its real sample size.** The model arm's build
hit a genuine, unseeded acceptance failure — `test_complaints_board_
renders_add_complaint_form`, 12/13 — an ordinary implement-phase content bug
(the POST form's method/action didn't match; the requirement itself *was*
present in the model's Phase 3 text, so this is not a decompose omission).
`RepairLoop` fired for real (no `--fixture` anywhere in this run) and round
1 reached 13/13 in 25s (`repair-round-1.json`, `acceptance.txt`). P12's own
verdict record lists this as unobserved: "a real implement failure feeding
real repair through to 13/13 has not been observed." **It is now observed
once, live and unseeded — not closed. n=1.** Filed into the verdict record
at that sample size, not as a resolved gap.

**Acceptance-equivalence: uncharacterized, per D4 — not a decompose
regression.** The baseline passed 13/13 on the first try; the model arm
needed one repair round. n=1-vs-n=1 cannot distinguish "decompose caused
this" from ordinary implement-phase variance (this project's own record:
an unchanged config swinging 0/2 → 2/2 → 1/2). Two further, incidental
confounds in this specific pair, noted for completeness rather than
explained away: the arms differ in pool size (3 vs 4 workers, by D1's
design) and in `run-config.json`'s recorded `availableBytesGiB` (100.9 vs
47.7 — almost certainly ambient system load between the two runs, not
caused by decompose, but recorded rather than silently omitted).

**P12.5 is closed on the structural disjunct.** Per the plan's own
done-when ("a model-authored packet passes validation and drives P12.4 to
the same result as a hand-authored one — or the gap is characterized"),
both halves are actually true here at once: the packet passed validation
and drove the run to the *same final result* (a passing acceptance run) as
the baseline, and the one gap between the arms (needing a repair round) is
characterized rather than glossed over.
