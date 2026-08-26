# Brief: why Mellum's repair rounds fix the symptom, not the file

**Date:** 2026-08-26. **For:** a fresh session/agent picking this up as its own task.
**Context you need:** SwiftStar (`/Users/pauleveritt/projects/pauleveritt/swiftstar`)
runs a local model (Mellum 2.1 or Laguna S 2.1) through a multi-phase coding
task via `swiftstar-agenttest`, graded by a real pytest acceptance suite.
P12.3 ("Mellum's arm") has been an open gap all along — Mellum was known not
to initiate tool calls under the plain agentic harness. An unrelated
overnight script (`Tools/overnight-chain.sh`) ran a large laguna/mellum
ablation the night of 2026-08-25→26 and is the source of the evidence below.

## The observation, with receipts

Capture `captures/agenttest/20260826-060458-roadmap`
(`mellum-2.1`, absolute paths, thinking on, seed 2):

1. **Build phase (worker 1, plain agentic, no text-contract):** `grep -c
   '"t":"tool_request"'` on worker 1's lines → **0**. Mellum narrated intent
   in prose ("I need to create a FastAPI application with Jinja2
   templates...") but never called a tool. Nothing was written. This matches
   the standing P13 finding — Mellum doesn't initiate tool calls in the plain
   harness — so the build phase produced no candidate.
2. **Repair (worker 2, `repairPacket` in `main.swift` always sets
   `textContract: true` regardless of the build arm's flag — this is
   existing P12.4/P15 design, not new):** Mellum switches modes and writes
   real code via labeled `#path` blocks. Two rounds ran:
   - **Round 1** grade: `ModuleNotFoundError: No module named 'app'`. Mellum's
     text correctly diagnoses this and emits a real `#app.py` block with a
     working FastAPI app, routes, and a `Complaint` dataclass inlined.
   - **Round 2** grade: `AttributeError: module 'models' has no attribute
     'complaints'`. Mellum correctly diagnoses *this specific* error and
     emits `#models.py` — but only `complaints: list[Complaint] = []`, an
     **empty list**. The spec requires seed complaints (e.g. a specific
     pre-populated complaint string) for several tests to pass.
   - Final grade: `10 failed, 3 passed` (`FFFFFFFFFF.FF`). Repair budget
     (2 rounds, `RepairLoop`'s default) exhausted. Run ends failed.

Each round's reasoning (visible verbatim in `wire.ndjson`'s `text` events for
worker 2) is *locally correct* — it reads the traceback, names the right
missing symbol, and writes plausible code for that one symbol. It never
revisits earlier files in light of the new failure, and never appears to
consider "does this file match the whole spec" — only "does this file fix
the error string in front of me."

## The question this brief is for

**Is this whack-a-mole pattern (fix exactly the reported symptom, once, per
round) characteristic of Mellum specifically, or would the same thing show up
if you gave it more rounds, or presented the *whole* current failure set
instead of one traceback at a time?** Concretely, distinguish between:

- **(a) A budget problem.** Mellum's diagnoses are each correct and
  convergent; it would reach a fully passing state in N rounds if given N,
  it's just that `RepairLoop`'s default cap (2) is too low for however many
  distinct missing pieces a from-scratch Mellum build leaves behind (recall:
  the build phase wrote *nothing*, so repair is reconstructing the whole app
  from tracebacks alone, one file at a time — that's a much bigger job than
  P12.4's original design target, which assumed a build phase had already
  written most of the app and repair was fixing one real bug).
- **(b) A framing problem.** Mellum only ever sees one failing test's
  traceback per round (check `repairPacket`'s evidence assembly — does it
  show the *first* failure, the full pytest output, or something truncated?)
  and literally cannot see that its `models.py` fix will still leave 10
  other tests red, because it's never shown their tracebacks in the same
  turn. If so, showing the full failure list (not just the first) might let
  it converge faster or in fewer rounds.
- **(c) A genuine reasoning-depth limit.** Even shown everything at once,
  does Mellum still patch symptom-by-symptom rather than reconstructing the
  file to match the spec holistically? (Compare against how Laguna behaves
  in the same repair role, from this same overnight run's laguna captures,
  or from the P12.4/P15 verdict records' existing repair evidence — Laguna's
  recorded repairs were single-file, single-bug fixes against an
  already-mostly-working app, which is a different task shape than "build
  the app from a stream of tracebacks with a 2-round cap." Is the comparison
  even fair?)

## Where to look

- `captures/agenttest/20260826-060458-roadmap` and `-064940-roadmap` (both
  mellum/absolute/on, different seeds) — read `wire.ndjson`'s worker-2 `text`
  events end to end, and `repair-round-1.json`/`repair-round-2.json` for the
  exact grade output each round actually saw.
- The full manifest, `/tmp/overnight-manifest.tsv` (40 mellum cells: relative
  ×2 path-styles × on/off thinking × 10 seeds) — once the chain finishes,
  check whether *any* mellum cell reached a passing acceptance run, and
  whether thinking on/off or path style correlates with how many distinct
  symptoms get whack-a-moled before the budget runs out.
- `Sources/SwiftStarAppKit/RepairLoop.swift` and `repairPacket` in
  `Sources/swiftstar-agenttest/main.swift` (~line 230-330) — confirm exactly
  what evidence (full pytest output vs. first failure only) each repair round
  actually receives, before assuming (b) is the explanation rather than
  checking it.
- The P12 verdict record and P12.4 design doc, for what repair's evidence
  contract was designed to assume (an already-working app with one bug) —
  worth stating plainly if Mellum's actual task (build-via-repair-from-
  nothing) is a different, harder problem than what repair was designed and
  measured against.

## Not in scope for this brief

Re-litigating whether Mellum "can write correct code" — P15 already
established it can, given a text-contract turn and shown the whole
surface. This is specifically about the *whack-a-mole* pattern: correct
local diagnosis, incomplete global fix, budget exhausted before convergence.
