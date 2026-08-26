# P11 addendum — the canonical agent test: first live run against Mellum 2.1 (2026-08-23)

> **Superseded as a live finding** by [`2026-08-25-local-model-agency.md`](2026-08-25-local-model-agency.md). Retained as the evidence record for the Mellum 2.1 live run's two distinct noChanges failure modes and the claims-vs-reality wire cross-check.

**Status:** first live run of `swiftstar-agenttest` against Mellum 2.1 (real Metal
inference, ds4 engine), n=1, easy + hard spec, matching the Laguna S 2.1
baseline methodology recorded in
`2026-08-23-p11-agenttest-verification-record.md`.

## Setup

- Model: `~/models/mellum-thinking-TARGET.gguf`, 9.33 GiB (Q4_K/Q8_0 selective,
  10,018,765,216 bytes on disk).
- Engine: `~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum`
  (branch `swiftstar-integration-mellum`, HEAD `cde6438`). Binaries confirmed
  fresh Metal builds before the run — `ds4-agent` is `Mach-O 64-bit arm64`,
  links `Metal.framework`, and carries 406 `ggml_metal_*`/Metal-kernel symbols
  and Metal kernel-pipeline error strings (i.e. not the `make cpu` fallback).
  No rebuild was needed.
- Engine load confirms Metal at runtime for both specs: `ds4: Metal device
  Apple M5 Max, 128.00 GiB RAM`, `resident model 9.33 GiB`, `backend=metal`.
- GPU was exclusive and free before and after: no `ds4-agent` process was
  running before the run, and none is running after (confirmed via `ps aux`).
- `AGENTTEST_THINK` was **not** set, so both runs used the harness's default
  `--nothink` worker mode (same default the Laguna re-runs used).

## Command

```bash
SWIFTSTAR_MODEL=~/models/mellum-thinking-TARGET.gguf \
DS4_DIR=~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum \
  swift run swiftstar-agenttest --spec roadmap             # easy
SWIFTSTAR_MODEL=~/models/mellum-thinking-TARGET.gguf \
DS4_DIR=~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum \
  swift run swiftstar-agenttest --spec roadmap-user-story   # hard
```

## Result — easy (`roadmap.md`)

Phase 1 stopped with a **`noChanges` receipt**. Capture:
`captures/agenttest/20260823-215911-roadmap/wire.ndjson`.

| Phase | Outcome | Tool calls | Mutations | Generated tokens | ctx_used | stop |
|---|---|---|---|---|---|---|
| 1 (home page) | **receipt `noChanges`** | **0** | **0** | 1359 | 3234 | eos |
| 2, 3 | not reached (transaction stopped) | — | — | — | — | — |
| **Acceptance** | not run (no final candidate) | — | — | — | — | — |
| **Grader** | not invoked (no final candidate) | — | — | — | — | — |

Wall clock: ~36s for the phase-1 turn (model already resident).

## Result — hard (`roadmap-user-story.md`)

Phase 1 also stopped with a **`noChanges` receipt** — reproducing the
documented "no agency" failure mode, exactly as expected per the task brief.
Capture: `captures/agenttest/20260823-220059-roadmap-user-story/wire.ndjson`.

| Phase | Outcome | Tool calls | Mutations | Generated tokens | ctx_used | stop |
|---|---|---|---|---|---|---|
| 1 (welcoming front door) | **receipt `noChanges`** | **0** | **0** | 470 | 2489 | eos |
| 2, 3 | not reached | — | — | — | — | — |
| **Acceptance** | not run | — | — | — | — | — |
| **Grader** | not invoked | — | — | — | — | — |

Wall clock: ~26s for the phase-1 turn.

## The most important finding: two different failure modes, and a claims-vs-reality cross-check

The task brief specifically asked to cross-check the model's own turn output
against the deterministic acceptance result and the actual git diff/file
contents — not just trust the transcript. Doing that surfaced **two distinct
failure modes**, one per spec, neither of which is the classic "claims tests
passed but they didn't" pattern (that gate was never reached — see below) —
but the easy-spec mode is adjacent to it and is the more important of the two:

**Easy spec — the model wrote a complete, plausible solution as chat text and never called a single tool.**
The reconstructed generation (concatenating every `"t":"text"` event) is a
full, syntactically correct implementation: `app.py` (FastAPI app, routes,
dataclass), `templates/base.html`, `templates/home.html`,
`templates/complaints.html`, and `tests/test_app.py` — five files, 130+
lines, presented file-by-file with filename headers and fenced code blocks.
It reads exactly like a finished submission. But the wire trace has **zero**
`tool`/`tool_request` events for the entire phase (`grep '"t":"tool'` on the
capture returns nothing), so the orchestrator's mutation tracker correctly
recorded 0 mutations and the transaction returned `noChanges`. **Nothing was
ever written to the worktree.** If you only skimmed the transcript — which is
exactly the failure mode the project's fabricated-validation finding warns
about — you would conclude the phase was implemented; the git diff (empty)
and the harness's own deterministic mutation count say otherwise. The harness
was *not* fooled (its receipt is accurate), but a shallow read of the model's
own output would be.

**Hard spec — the model announced a plan and then stopped, generating no code at all.**
The reconstructed text is nine short lines: "We are going to create the
following files: ... Let's write each file one by one." — then `stop_reason:
eos` with only 470 tokens generated, again zero tool calls. This is a purer
form of the "no agency" pattern the Laguna hard-spec run showed (Laguna at
least got 6 mutations into phase 1 before declining on phase 2), but here
Mellum didn't even attempt to draft file content on the *easy* spec's
sibling — it stopped after stating intent.

**Net read:** in both runs, the model's turn output and the deterministically
verified reality (0 tool calls, 0 mutations, empty git diff, `noChanges`
receipt) point the same direction — nothing was built — so there is no case
of the harness's acceptance/grader layer being fed a false "success" claim
here (that gate was never reached, because no candidate was produced to
grade). The divergence that matters is upstream of that gate: the easy-spec
transcript *looks* like a completed, correct implementation to a casual
reader, while the deterministic mutation count and git diff show nothing
happened. That is the fabrication-adjacent risk the task asked to watch for,
even though in this instance the harness's own accounting caught it cleanly
before it could reach acceptance or the grader.

## DeepSeek grader — confirmed wired and live, but not exercised by either Mellum run

Per commit `accbea6`, `main.swift` calls `DeepSeekGrader.grade(...)` and
writes `code.md`/`rubric.md`/`verdict.json` to the capture dir — but only
after `txn.commitBack()` succeeds (i.e., only for a `.completed` run). Since
both Mellum runs stopped at phase 1 with a `noChanges` receipt, **the grader
was never invoked by either run** — there was no final candidate to grade,
and this is the correct/expected behavior of the gating logic, not a gap.

To confirm the grader path is actually live right now (not just wired in
source), I replicated the harness's exact request (same endpoint, model,
prompt template, and `~/.pi/agent/auth.json` `openrouter-curated` key
resolution) against the **reference** implementation
(`fixtures/agenttest/reference/`), out-of-band and without using the GPU:

```json
{"verdict":"good","reasons":["Correctly implements FastAPI with all required
  routes","Properly uses Jinja2 templates with base.html inheritance",
  "Includes all specified HTML5 and Bootstrap 5 elements", ...]}
```

This matches the original record's sanity check exactly (same reference
code, same "good" verdict). `GraderVerdict.parse` strips the ` ```json `
fence the model wrapped the reply in (extracts between first `{` and last
`}`), so this response parses to `.good` via the same compiled path
`main.swift` uses. **Confirmed live and correctly wired**; it simply had no
candidate to grade on Mellum today.

## What this establishes (n=1)

- Mellum 2.1, run under the harness's default `--nothink` mode, failed to
  engage the tool-calling contract at all on **both** specs — not just the
  hard one. This is a stronger agency failure than Laguna showed: Laguna
  reliably won the easy spec in the first live run (3/3 phases, acceptance
  green) and only failed to act on the outcome-only hard spec's phase 2.
  Mellum failed phase 1 of *both* specs, with zero tool calls in either.
- The failure shapes differ by spec: the easy spec produced a fully-formed
  fabricated-looking answer with nothing behind it; the hard spec produced
  only a stated intent and stopped. Both are caught cleanly by the harness's
  deterministic mutation tracker (`noChanges` receipt) — the acceptance suite
  and DeepSeek grader were never reached because the gating logic correctly
  never handed them anything to grade.
- The DeepSeek grader is confirmed wired end-to-end and live (verified via an
  out-of-band replica call returning the expected verdict on the reference
  code), even though this specific pair of runs didn't reach it.

## What it does not establish

- n=1 per spec — no variance data for Mellum the way the Laguna record's
  n=4 easy batch exists. Given the Laguna instrument was already documented
  as bimodal (some runs think-thrash to the context limit, some complete
  concisely, some fail acceptance even when they complete), a single Mellum
  run per spec cannot distinguish "Mellum reliably fails to call tools under
  this harness" from "this was one unlucky roll." A `--batch` re-run would be
  needed to tell those apart.
- Whether Mellum's zero-tool-call behavior is specific to `--nothink` mode,
  to this handoff-packet prompt shape, or to Mellum's chat/tool template in
  this ds4 build was not investigated — that would require an
  `AGENTTEST_THINK=1` comparison run and/or inspecting the tool-schema
  portion of the prompt actually sent to the engine.
- No acceptance-suite or DeepSeek-grader verdict exists for Mellum's output
  on either spec, because no candidate was ever produced to grade.

## Housekeeping

- No files outside `captures/agenttest/` and this record were modified;
  `git status --short` and `git diff --stat` are clean apart from
  pre-existing untracked files unrelated to this run.
- The ds4 submodule pin and the SwiftStar app itself were not touched — this
  was an eval-only run against an external worktree engine build.
- GPU lock confirmed released: no `ds4-agent` process running after the run.

## Follow-up (same day): `DS4_AGENT_TOOL_NUDGE=2` under `--host-tools`, n=1 easy spec

**Question:** does the one documented mitigation for Mellum's "narrates instead
of calling tools" failure — the engine's bounded corrective nudge,
`DS4_AGENT_TOOL_NUDGE` (`ds4_agent.c:494-507`, consumed in `worker_run_turn`
at ~14142/~14460) — actually reach and affect a turn run through
`PoolOrchestrator`'s `--host-tools` path? MELLUM.md's own prior measurement
(`DS4_AGENT_TOOL_NUDGE=2` turning 0 tool calls into 8, 2/4 files) predates
host-tools and was taken on the standalone engine path, so it does not by
itself establish this.

### Step 1 — accounting check: does the nudge gate look at the right signal under `--host-tools`?

Read `ds4_agent.c` closely around the gate (`worker_run_turn`, ~14260-14487)
and around `agent_execute_tool_calls` (~13409-13460, the `--host-tools`
bidirectional-wire dispatcher). Finding, concretely:

- The nudge fires on `bool got_tool`, which is set **only** by the DSML/tagged
  tool-call parser reaching `AGENT_DSML_DONE` with `calls.len > 0`
  (`ds4_agent.c:14392-14393`, confirmed again at `:14414-14415`) — i.e. purely
  from whether the model's own token stream contains a syntactically parseable
  tool-call, decided token-by-token in the same per-round generation loop for
  both host-tools and non-host-tools runs.
- `agent_execute_tool_calls` — the function containing the `--host-tools`
  bidirectional wire (`w->cfg->host_tools` branch at `:13412`, emit
  `tool_request` / block on stdin `tool_result`) — is only ever called
  **after** `got_tool` is already true (call site `:14538`, inside the `else`
  branch that is unreachable when `nudge_now`/`malformed_tool`/`early_tool_error`
  are set). So host-tools execution verdicts (ok:true/false, refusals) happen
  strictly downstream of the nudge decision and never feed back into it.
- Conclusion: for Mellum's specific failure mode — the model emits **zero**
  tool-call syntax at all, only narration — `got_tool` is false regardless of
  `--host-tools`, so the nudge gate's signal is unaffected by host-tools mode
  and does **not** silently no-op for this case. (A different scenario — model
  emits a syntactically valid call that the host then refuses via `ok:false`
  — would already have `got_tool=true` and never reach the nudge gate at all;
  that's a separate, unrelated code path and not what Mellum is doing here.)
- Environment plumbing confirmed separately: `PoolOrchestrator.swift:29,38,46`
  copies the full parent `ProcessInfo.processInfo.environment` into the
  `ds4-agent` child process (only adding `DS4_METAL_*_SOURCE` vars on top), and
  `AgentCommand.swift:57-62` always passes `--json-events --host-tools`. So
  `DS4_AGENT_TOOL_NUDGE` set on the harness invocation reaches the engine
  subprocess unmodified.

**Verdict: the accounting is correct.** The nudge is engine-generation-side
and syntax-only; it is not blind under `--host-tools` for the "zero tool
calls" pattern this task is chasing. This is a genuine test of the mitigation,
not a no-op.

### Step 2 — n=1 easy spec (`roadmap.md`) with `DS4_AGENT_TOOL_NUDGE=2`

```bash
DS4_AGENT_TOOL_NUDGE=2 SWIFTSTAR_MODEL=~/models/mellum-thinking-TARGET.gguf \
DS4_DIR=~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum \
  swift run swiftstar-agenttest --spec roadmap
```

Capture: `captures/agenttest/20260823-221314-roadmap/wire.ndjson`. Result:
**phase 1 again stopped with a `noChanges` receipt** — same outcome as the
un-nudged baseline above. But the wire trace shows the nudge mechanism
*did* engage, exactly as configured:

- **3 generation rounds** for the worker, not 1: round 1 prefills the full
  packet (`prefill_total=1066`, generates to ~1055 tokens, no tool call);
  round 2 begins with a small incremental prefill (`prefill_total=49` — the
  injected "Continue the original request..." correction appended on top of
  the existing KV cache, generates to ~1095 tokens, no tool call); round 3
  begins with another `prefill_total=49` (second nudge, generates to 1105
  tokens, no tool call, ends `stop_reason: eos`). Two nudge rounds = exactly
  `nudge_max=2` as set — the mechanism consumed its full budget before the
  turn ended, matching the `nudges_used < nudge_max` → exhausted →
  `AGENT_TURN_STOP_EOS` path in the source.
- **Zero `tool`/`tool_request` events across the entire capture**
  (`grep -c '"t":"tool' wire.ndjson` → 0, all 3 rounds included).
- **What the model actually did with each nudge**: reconstructing the text
  per round shows round 2 opens with "I need to continue the original
  request. The user wants me to create the home page for AgentClinic. I've
  already created the files `app.py`, `templates/base.html`, and
  `templates/home.html`. Now I need to create `templates/complaints.html` and
  `tests/test_app.py`..." and then resumes writing fenced code blocks as chat
  text — never a tool call. Round 3's opening ~400 characters are
  near-byte-identical to round 2's (same files, same narration, same
  ordering) — the model treated the nudge as a cue to keep narrating from
  where it left off, not as an instruction to switch to tool-call syntax.
  Total generation across the turn grew from baseline's 1359 tokens (1 round,
  no nudge) to ~3256 tokens across 3 rounds here, and `ctx_used` grew from
  3234 to 5247 — the nudge cost real context budget and wall clock for no
  behavioral change.

### Step 3 — hard spec: not run

Per the task's own gating (`if tool calls still don't appear: don't try
further engine-side knobs, stop, report`), the hard spec was **not** run,
since step 2 already shows zero tool calls under the nudge on the easy spec.

### Net finding

This is a genuine **"the fix doesn't help"** result, not a "the fix didn't
get a fair test" result. The nudge mechanism is correctly wired for
`--host-tools`/pool-path turns (step 1), the environment variable correctly
reaches the engine subprocess, and it visibly fired exactly twice as
configured (step 2) — but Mellum's response to the corrective message was to
keep re-narrating a plausible-looking answer as chat text rather than switch
to tool-call syntax, in both nudge rounds. The one documented mitigation for
this failure mode does not fix it under the harness's actual `--host-tools`
pool path. No further engine-side knobs were tried, per the task's stop
condition. GPU lock confirmed released after this run (`ps aux` shows no
`ds4-agent` process); no files outside `captures/agenttest/` and this record
were modified.
