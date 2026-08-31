# P7 verification record (2026-08-22)

Durable record for Phase P7 ("Agent mode"). Executed on branch `p7-agent-mode`,
spec-driven per `docs/sdd.md`.
Spec: [`docs/superpowers/specs/2026-08-22-p7-agent-mode-design.md`](../specs/2026-08-22-p7-agent-mode-design.md).
Plan: `docs/superpowers/plans/archive/2026-08-22-p7-agent-mode.md`.

## Test evidence

- **Fast tier** (`just test`): 162 tests in 28 suites green; the six
  integration-gated suites (`CaptureWriterTests`, `FakeAgentIntegrationTests`,
  `FakeServerIntegrationTests`, `FixtureReplayTests`, `ProcessStatsCollectorTests`,
  `DownloadIntegrationTests`) skipped — no model, no network, no subprocess
  (tripwire-guarded). New P7 fast suites: `AgentWireParserTests` (handshake
  enforcement + the `ready` turn-outcome fields + `golden`/`golden-tools`
  parsing), `AgentTranscriptTests` (tool-card reducer, the leading-newline
  quirk, the post-`finish` `output` attribution), `TurnOutcomeTests` (the
  builder's lifecycle/stop-reason matrix), `AgentCommandTests` (the argv
  contract incl. `--workspace`/`--shell`), `FakeAgentSourceTests` (determinism).
- **Integration tier** (`just integration`): 162 tests in 28 suites green — the
  six gated suites now run. New P7 integration: `FakeAgentIntegrationTests`
  spawns the fake `ds4-agent` (generated from the real tool capture) via the
  production `AgentCommand` argv; the harness asserts argv validation
  (`fakeRefusesWrongArgv`, incl. `--workspace`/`--shell`), a full stream → a
  transcript with tool cards (`fakeReplaysCaptureEventsEquivalently`), and
  interrupt — ETX → the fake emits an interrupted `finish`, a `ready` carrying
  `stop_reason: interrupt`, and stops (`fakeHonorsETXAsInterrupt`).
- **Engine tier** (`make -C external/ds4 test`): the P7-relevant suites are green
  — `ds4_agent_test` ("ds4-agent tests: ok") and `ds4-eval --self-test-extractors`
  ("answer extractor self-tests passed"). `ds4_test` is **not** fully green:
  pre-existing environmental sections fail identically pre/post P7 (Ruling 4 —
  missing official-API reference vectors, SSD-streaming unimplemented for this
  model, `DS4_TEST_MODEL` fixtures such as `ds4flash.gguf` that are not on this
  machine, metal-short-prefill drift). The first failure is `long-context`
  (`cannot open model 'ds4flash.gguf'`). `ds4_test` does not link `ds4_agent.c`,
  so the P7 engine patch (consent flags + the `ready` turn-outcome fields) is
  exercised only by `ds4_agent_test`, which is green. Recorded here rather than
  treated as a regression.
- **Live tier** (`just capture`, manual, never CI): the recapture at the P7
  submodule bump produced `fixtures/agent/golden.ndjson` (recaptured — 45 lines:
  the wire contract re-verified at the new SHA) and the new
  `fixtures/agent/golden-tools.ndjson` (the tool-event fixture, D7). The
  golden-tools capture is the live-tier proof of the D12 wire addition: its five
  turn-end `ready` events each carry `stop_reason` (see below).

## Outcome-telemetry evidence (D12)

`golden-tools.ndjson` is a verbatim copy of `ds4-agent`'s stdout from one real
`--json-events` session exercising the file/shell tool zoo (122 lines: 1
`hello` + 6 `ready` + 51 `status` + 24 `text` + 40 `tool`). The stop-reason
greps against the fixture:

- `grep -c '"stop_reason"' golden-tools.ndjson` → **5**; all five are
  `"stop_reason":"eos"` (the startup `ready` omits the field, as designed — the
  turn-outcome fields ride only the turn-end `ready`).
- The five turn-end `ready` events carry `generated`/`ctx_used` too:
  `(21, 1134)`, `(18, 1238)`, `(28, 1430)`, `(17, 1522)`, `(22, 1648)` —
  `ctx_used` climbing across the turns, the memory-plan fields unchanged.
- The tool-phase zoo: 5 `start`, 5 `tool`, 8 `param_begin`/`param_value`/
  `param_end`, 5 `finish`, 1 `output` — five tool blocks (`read`, `list`,
  `write`, `edit`, `bash`), eight parameters total, and the single `output`
  (bash) arriving **after** its block's `finish` (the post-`finish` `output`
  attribution the transcript reducer pins).

The `goldenToolsYieldsFullLifecycleOutcomes` test (integration tier) feeds the
whole fixture through `AgentWireParser` → `TurnOutcomeBuilder` and asserts the
evidence floor (binding rule 6): the tool calls are non-empty, every call's
first transition is `.emitted`, the `bash` call reaches `.executed` (it has an
`output` phase), the `read` call reaches `.parsed` (a clean `finish`), and the
stop reason is one of the typed cases (`eos`/`limit`/`interrupt`/`contextFull`).
The fixture, not a hand-authored vector, is what proves the D12 wire addition
against the real binary.

## Shown-fail records (binding rule 2)

Every new test was shown to fail before its implementation passed (binding rule
2: in a compiled language, "fail" = the test target does not compile or the
assertion fails). Representative pins:

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| handshake enforcement (T6) | accept a non-v1 `hello` / missing caps | `unknownVersionRefuses`, `missingRequiredCapRefuses`, `firstNonBlankLineMustBeHandshake` fail | yes |
| workspace confinement (T2) | resolve a path that escapes `--workspace` | the engine `read`/`write`/`edit` confinement test fails (out-of-workspace path refused) | yes |
| shell-off gating (T1) | advertise `bash` under `--shell off` | `test_agent_glm_tools_prompt_is_native`'s shell-off sibling fails (bash dropped; `google_search`/`visit_page` survive) | yes |
| turn-outcome stop reason (T3/T7) | omit `stop_reason` from the turn-end `ready` | `readyCarriesTurnOutcomeFields`, `cleanReadCallIsEmittedParsedExecuted`, `goldenToolsYieldsFullLifecycleOutcomes` fail | yes |
| ETX interrupt (T10/T11) | emit a bare `ready` (no `stop_reason: interrupt`) on ETX | `fakeHonorsETXAsInterrupt` fails (asserts the interrupted `finish` + `ready` carrying `stop_reason: interrupt`) | yes |
| outcome-orphan (T12) | finish the builder only when `stopReason != nil` | a turn-end `ready` omitting the field left `outcomeBuilder` non-nil — the record never written | yes |

## Real bugs found during P7

Bugs the tests, the live tier, or the implementer caught before they shipped
(the plan-text defects would have been code bugs had the implementer not
caught them — they are recorded, not hidden):

1. **The fake agent hung at `FAKE_SPEED=0`.** `FakeAgentSource.replayOnce()`
   slept unconditionally; `lineDelay` divides by `speed`, so speed 0 → an
   infinite interval → the integration tier hung on the first line. Fixed by
   guarding `if speed > 0 { Thread.sleep(...) }` (mirroring `FakeServerSource`).
   [Task 10]
2. **The capture driver appended to `Process.arguments` in vain.**
   `Process.arguments?.append(...)` mutates a value-type copy, so the
   workspace/shell flags never reached the spawned `ds4-agent`. Fixed by
   building the argv on a local var and assigning it. [Task 5]
3. **The args pointer was a NULL deref waiting to happen.** The plan's Task 1
   test built `agent_tool_call call = {0}` then wrote `call.args[0]` — but
   `args` is `agent_tool_arg *` (a pointer), so `args[0]` dereferenced NULL.
   Caught by the implementer; fixed with a stack `agent_tool_arg args[1] = {0};
   call.args = args;`. [Task 1, Ruling 2 — plan-text defect caught before it
   shipped]
4. **macOS `/tmp` canonicalizes to `/private/tmp`.** The Task 2 confinement
   test's verbatim `strncmp` against `/tmp/...` was self-inconsistent with its
   own `realpath`-based implementation (which resolves to `/private/tmp/...`).
   Adapted to compare against `realpath(tmp)` — portable and intent-preserving.
   [Task 2, environmental]
5. **The baseline engine tests asserted pre-`ts` exact strings.** At the pinned
   submodule commit, 11 `DS4_AGENT_TEST` assertions checked literal `"}\n` tails,
   but divergence #7 added `,"ts":<µs>` to every event — the test debt was never
   committed with the emitter change. Reproduced in the main repo at the same
   commit (the commit, not the environment). Task 0 made the 11 assertions
   `ts`-robust before any P7 engine work landed. [Task 0, Ruling 1 — fork test
   debt]
6. **`CAPTURE_WORKSPACE`'s chdir broke the engine's cwd-relative Metal sources.**
   The recapture driver `chdir`s into the workspace; the engine loads Metal
   sources relative to cwd, so the live capture failed to find them. Fixed by
   setting `DS4_METAL_*_SOURCE` absolute overrides in the driver. [Task 5,
   environmental — a latent engine constraint, filed separately]
7. **The turn outcome orphaned on a `ready` without a wire stop reason.**
   `AgentController` finished the `TurnOutcomeBuilder` only when the turn-end
   `ready` carried a non-nil `stopReason`; a pre-D12 wire (or any `ready`
   omitting the field) left the builder non-nil — the record never written, the
   next turn orphaned. Fixed by finishing unconditionally on any turn-end
   `ready` (the builder is nil at startup, so a startup `ready` is a no-op);
   `TurnOutcomeBuilder.finish` defaults a nil wire reason to `.eos`. [Task 12]
8. **`agent_build_tools_prompt` has two call sites, not one.** The plan threaded
   the shell flag through a single call site; the source has two
   (`ds4_agent.c` ~:1373 and ~:1390 — GLM and Laguna). Both were threaded with
   `w->cfg->shell_allowed` — the un-threaded one would have advertised `bash`
   under `--shell off`. [Task 1, Ruling 3 — plan-text defect caught before it
   shipped]

## Concept budget

**workspace**, **tool card**, and **turn outcome** are now defined (see
ROADMAP). The seed terms **handoff packet** and **candidate ref** remain
unrelated and stay undefined until their phases land.

## Scope compliance

P7 shipped what the spec's Components section lists and nothing the Out-of-scope
section defers. In: the Agent tab (`AgentController` + `AgentView`), the NDJSON
transcript with tool cards (`AgentWireParser` + `AgentTranscript`), the
spawn-time consent controls (`--workspace` confinement + `--shell` gating,
`AgentCommand.argv`), interruptible turns (ETX), capture-grade turn/tool
outcomes (D12: `TurnOutcome`/`TurnOutcomeBuilder` + the engine `ready`
`stop_reason`/`generated`/`ctx_used` fields), and the two fixtures
(`golden.ndjson` recaptured, `golden-tools.ndjson` new). Out, and deliberately
deferred: live Metrics/Diagnostics from the spawned agent (D9 — the P4
sequencing bullet is amended below with the dated correction); web-tool consent
(D11 — the engine's existing terminal-UI approval stays); think-effort control
(D10 — `think` is handled, not toggled); a live mid-turn consent change
(spawn-time only; P9 enables live toggles); per-tool consent on the wire,
tool-result condensation, and a fake *app* side (all P9). No `ds4-server`
capture, no CI automation of the live tier. The P4 bullet's claim that the live
wiring "lands with P7's `ds4-agent` migration" is corrected below.
