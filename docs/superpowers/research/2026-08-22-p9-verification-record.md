# P9 verification record (2026-08-22)

Durable record for Phase P9 ("The tool-callback wire"). Executed on branch
`p9-tool-wire`, spec-driven per [`docs/sdd.md`](../../sdd.md).
Spec: [`docs/superpowers/specs/2026-08-22-p9-tool-callback-wire-design.md`](../specs/2026-08-22-p9-tool-callback-wire-design.md).
Plan: [`docs/superpowers/plans/archive/2026-08-22-p9-tool-callback-wire.md`](../plans/archive/2026-08-22-p9-tool-callback-wire.md).

## Test evidence

- **Fast tier** (`just test`): **237 tests in 34 suites passed**, 0 failures
  (0.290 s). The integration-gated suites are skipped — no model, no network, no
  subprocess (tripwire-guarded). New P9 fast suites: `ToolCallbackResponderTests`
  (18 — the consent matrix: file tools proceed inside the workspace, escapes and
  absolute/sibling paths refuse, `bash` is shell-gated, web tools always refuse,
  unknown tools refuse; `respond` executes and carries the condensed result or
  `ok:false`; the `tool_result` line is valid JSON with sorted keys and escaped
  specials), `ToolResultCondenserTests` (7 — cap/digest, deterministic, default
  8000, multibyte cuts on boundaries), `FakeAppSourceTests` (7 — determinism,
  embedded answers, the fixed refusal, empty-answers, source compiles). Extended
  suites: `AgentWireParserTests` (5 — `tool_request` parses, multi-param order,
  empty/omitted/missing-name), `AgentCommandTests` (2 — `argv` carries
  `--host-tools` by default and `-sys` lands after it), `TurnOutcomeTests` (5 —
  host-fact fields default/settable, `hostModeToolRequestRecordsEmitted`, and the
  accumulate-across-blocks/bash calls cases), `FakeAgentSourceTests` (6 —
  `hostToolsOffMatchesObservationByteForByte`, `hostToolsEmitsToolRequest`,
  `hostToolsSkipsToolPhaseStream`, `hostToolsRequestCarriesNameAndParams`,
  `hostToolsStillEmitsNonToolLines`, `hostToolsDeterminism`).
- **Integration tier** (`just integration`): **237 tests in 34 suites passed**,
  0 failures (3.383 s) — the gated suites now run. New P9 integration:
  `FakeHostToolsIntegrationTests` (5 — see "Round-trip evidence" below).
  `FakeAgentIntegrationTests` extends to the host-tools argv
  (`fakeRefusesWrongArgv` carries `--host-tools`).
- **Engine tier** (`make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`):
  **`ds4-agent tests: ok`** (exit 0). The P9 engine patch (`--host-tools`,
  `agent_execute_tool_calls` host mode, the `hello` `caps` closure) is exercised
  by `ds4_agent_test`, which is green — including the new
  `test_agent_emit_hello_caps_array_closes` regression (see "Real findings"). The
  fork-ledger row #10 (`docs/fork-ledger.md`) and the `json-events.md` host-tools
  addendum document the two new message kinds.
- **Live tier** (`just capture`, manual, never CI): the recapture at the P9
  submodule bump (`c21b831`) produced the recaptured `fixtures/agent/golden.ndjson`
  (41 lines: the wire contract re-verified at the new SHA) and the recaptured
  `fixtures/agent/golden-tools.ndjson` (the tool-event fixture, re-verified). Both
  were copied to the bundled `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}`
  so `FixtureReplayTests.bundledFixtureMatchesRepoFixture` (bundled == repo) stays
  green. See "D1 evidence" and the provenance files for the per-fixture detail.

## Round-trip evidence (`FakeHostToolsIntegrationTests`)

The `--host-tools`-on round trip is proven by `FakeHostToolsIntegrationTests`
(integration tier), not by the live capture — `swiftstar-drive` tees stdout and
cannot answer a `tool_request`, so the live `golden-tools.ndjson` is the
**observation-only** `tool` phase stream (`--host-tools` off). The round trip uses
two fakes compiled from the committed capture:

- `FakeAgentSource.generate(capture:, hostTools: true)` builds a fake `ds4-agent`
  that replaces each tool block with a `tool_request` event (one per `finish`) and
  blocks reading a `tool_result` from stdin — mirroring the engine's
  `--host-tools` protocol over a shared pipe.
- `FakeAppSource.generate(answers:)` builds a fake app that reads `tool_request`
  lines and answers with canned `tool_result` lines (keyed by name, `ok:true`;
  unkeyed names get the fixed refusal, `ok:false`).

The five tests:

- `roundTripFakeAgentAndFakeApp` — the full round trip: the fake agent emits one
  `tool_request` per tool block in the `golden-tools` capture (`nRequests` counted
  from its `finish` events), the harness forwards each request to the app and
  relays the app's `tool_result` back; the agent consumes the result and
  continues. Asserts `reqCount == nRequests`, no observation-only `tool` phase
  stream leaks (`host-tools mode must not emit the observation-only "tool" phase
  stream`), and the agent reaches the turn-end `ready` with `stopReason:"eos"`.
- `roundTripRefusedResultsDoNotHang` — when the app answers every request with
  `ok:false` (empty answers), the agent still consumes the result and continues to
  the turn-end `ready`; it does not hang waiting for a success it will never get
  (`ok:false` is a result, not an absence).
- `fakeAppAnswersKeyedName` / `fakeAppRefusesUnkeyedName` / `fakeAppIgnoresNonRequestLines`
  — the app answers a keyed name with `ok:true` + the canned `s`, refuses an
  unkeyed name with `ok:false` + the fixed refusal (echoing `idx` untouched), and
  silently skips non-`tool_request` lines (the shared-stream discipline).

The round trip is asserted by naming the fixture (`golden-tools.ndjson`), not by
hand-authoring the request stream — the evidence-floor rule from the spec.

## D1 evidence (the bare wire is unchanged)

The P9 bump adds `--host-tools` (divergence #10); the flag is **off by default**,
so the bare-CLI wire is **observation-only** — the engine executes tools internally
and emits the `tool` phase stream, never a `tool_request`. The recapture proves D1
against the real binary at `c21b831`:

- `golden.ndjson`: `grep -c "tool_request"` → **0**; `grep -c '"stop_reason"'` →
  **2** (both `"eos"`); `grep -c '"t":"ready"'` → **3** (1 startup + 2 turn-ends);
  `golden.trace` has **2** `prefill sync done` lines; `planned_bytes` is still
  `49_943_965_040`. The `hello` `caps` are the same seven kinds as P5/P7
  (`tool_request` appears only when the flag is set).
- `golden-tools.ndjson`: `grep -c "tool_request"` → **0** (engine-internal
  execution); the tool zoo (`write`/`read`/`edit`/`list`/`bash`, 5 `start`/`tool`/
  `finish`, 8 `param_*`, 1 bash `output` = `"hello-world\n"`); 5 `stop_reason:"eos"`
  on the turn-ends; 6 `ready`; `seed.txt` created **inside** the workspace
  (`hi from golden-tools` — the `write` ran, then the `edit` replaced
  `hello`→`hi`), none leaked into `external/ds4/`.

The count/band drift vs the P7 recapture (`35bf505`: 45 lines / 20 `status` /
5833 bytes) is cadence only: the P9 recapture is 41 lines / 18 `status` / 5291
bytes. The test-critical values are unchanged (`planned_bytes`, 2 prefill syncs,
text-only + `tool_request`-free). `DiagnosticsEvidenceFloorTests.acceptsKnownGoodGoldenCapture`
stays green (no critical findings).

## Shown-fail records (binding rule 2)

Every new test was shown to fail before its implementation passed (binding rule 2:
in a compiled language, "fail" = the target does not compile or the assertion
fails). Representative pins:

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| host-tools off == observation byte-for-byte (T1) | generate with `hostTools:true` not replacing the `tool` stream | `hostToolsOffMatchesObservationByteForByte` / `hostToolsSkipsToolPhaseStream` fail | yes |
| `tool_request` carries name + params (T2) | emit a request without `name`/`params` | `hostToolsRequestCarriesNameAndParams` / `toolRequestParses` fail | yes |
| consent refuses escapes / off-shell / web (T3) | let a `..`-escape or shell-off `bash` proceed | `consentRefusesPathEscapeViaDotDot` / `consentRefusesShellWhenOff` / `consentRefusesWebTools` fail | yes |
| `tool_result` is valid JSON, sorted, escaped (T4) | emit a malformed or unsorted result line | `resultLineIsJsonToolResult` / `resultLineKeysAreSorted` / `resultLineEscapesSpecialCharacters` fail | yes |
| the round trip continues to `eos` (T5/T6) | drop the relay or the `ok:false` continue | `roundTripFakeAgentAndFakeApp` / `roundTripRefusedResultsDoNotHang` fail | yes |
| `hello` `caps` array closes (P9 regression) | remove the `"]"` after the conditional `,"tool_request"` | `test_agent_emit_hello_caps_array_closes` — 2 assertion failures (`strstr … "\"queued\",\"ts\"]"` and `… "\"tool_request\"]"` both NULL); `ds4_agent_test` exits 1 | yes |

## Real findings during P9

Bugs the tests, the live tier, or the implementer caught before they shipped:

1. **The `hello` `caps` array was never closed (the live recapture caught it).**
   The `741f722` commit that added the conditional `,"tool_request"` into
   `agent_emit_hello` dropped the `"]"` the parent `b91401d` closed the `caps`
   array with, so the emitted `hello` was invalid JSON
   (`{"t":"hello","v":1,"caps":["status",…,"queued","ts","ts":<n>}` — the array
   never closed, and `,"ts":<n>` landed inside it). The live recapture refused it
   (`wire handshake refused`; `python3 -c json.loads` confirmed invalid at column
   85). `ds4_agent_test` did **not** catch it — no C test parsed the `hello` JSON,
   so the defect shipped green in the engine tier. The `c21b831` amend closes the
   `caps` array after the conditional and adds
   `test_agent_emit_hello_caps_array_closes` (red-then-green: 2 failures without the
   `"]"`, 0 with). This is the defect the recapture-on-every-bump rule exists for,
   and exactly why the dispatch front-loads the recapture before the gitlink bump.
   [Task 6, the close]
2. **The gitlink was still `b91401d`.** The engine patch was committed in the
   submodule (`741f722`, then amended to `c21b831`) but the parent's gitlink still
   pointed at `b91401d`. Bumped in its own commit
   (`P9: bump submodule — --host-tools tool-callback wire (divergence #10)`) so the
   recapture and the bump are separately auditable. [Task 6]

## Concept budget

**tool request**, **tool result**, and **host tool execution** are now defined
(see ROADMAP). The seed terms **handoff packet** and **candidate ref** remain
undefined until P10/P11.

## Scope compliance

P9 shipped what the spec's Components section lists and nothing the Out-of-scope
section defers. In: the engine `--host-tools` flag + `agent_execute_tool_calls`
host mode (emit `tool_request`, block on `tool_result`, the `hello` `caps`
closure, the fork-ledger row + `json-events.md` addendum); `AgentWireParser`
`.toolRequest`; `ToolResultCondenser` (pure, deterministic cap/digest);
`ToolCallbackResponder` (consent + execution + condensation, host facts);
`FakeAppSource` (the fake app side); `TurnOutcome` host-fact fields;
`AgentController` routing `tool_request` → responder → `tool_result` over stdin;
the fake-agent ↔ fake-app round trip (`FakeHostToolsIntegrationTests`); and the
recaptured fixtures (`golden.ndjson`, `golden-tools.ndjson`, bundled
`golden.{ndjson,trace}`). Out, and deliberately deferred: worktree isolation and
the handoff packet (P10); subagent dispatch (P11); the web tools' consent (still
the wire, not widened here). No live `--host-tools`-on capture (the driver cannot
answer `tool_request`); the round trip is the fakes, not the real engine.
