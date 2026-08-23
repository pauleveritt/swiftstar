# P9 — The Tool-Callback Wire: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: subagent-driven-development (or executing-plans). `- [ ]` checkboxes.

**Goal:** Make the agent wire bidirectional: `--host-tools` turns the agent's tool calls into `tool_request` events that block on `tool_result` lines from stdin; the app executes + condenses + answers; a fake app side covers the integration tier; outcome telemetry gains the host-authoritative facts.

**Architecture:** Engine patch at the single dispatch chokepoint (`agent_execute_tool_calls`); `AgentWireParser` + `ToolResultCondenser` + `FakeAppSource` in Kit; `ToolCallbackResponder` + `AgentController` routing in the app; the fake agent gains a `--host-tools` mode.

**Tech Stack:** Swift 6.3 + C (`ds4_agent.c`); the fork's `DS4_AGENT_TEST` harness.

**Spec:** `docs/superpowers/specs/2026-08-22-p9-tool-callback-wire-design.md`

## Global Constraints

- Fast tier (`just test`): no model/network/subprocess. Integration (`just integration`): real processes against fake engine + fake app binaries. Live (`just capture`): real engine.
- Binding rule 2 (shown-fail), rule 6 (evidence floor: fake app generated from the committed capture; round trip asserted by naming the fixture), rule 7 (a result for an unknown idx refuses loudly).
- Bare CLI unchanged: without `--host-tools` the engine executes internally, byte-for-byte as today (D1).
- No new tool semantics (D6): the host runs what the consent flags already permit.

## File Structure

- Engine: `ds4_agent.c` (`--host-tools` flag; host-mode dispatch; stdin line reader), `docs/json-events.md` (two message kinds), `docs/fork-ledger.md` (row #10).
- Kit: `AgentWireParser.swift` (`.toolRequest`), `ToolResultCondenser.swift`, `FakeAppSource.swift`, `TurnOutcome.swift` (host-fact fields).
- App: `ToolCallbackResponder.swift` (new), `AgentController.swift` (route + write back).
- Tests: `ToolResultCondenserTests`, `AgentWireParserTests` (extend), `FakeAppSourceTests`, `TurnOutcomeTests` (extend), `ToolCallbackIntegrationTests` (new).

---

### Task 1: Engine — `--host-tools` + the request/result protocol

**Files:** `external/ds4/ds4_agent.c`; unit tests in `DS4_AGENT_TEST`.

**Interfaces:** `agent_config.host_tools: bool` (default false); `--host-tools` arg; a blocking NDJSON line reader over stdin (`agent_stdin_read_line`); `agent_execute_tool_calls` in host mode emits `{"t":"tool_request","idx":N,"name":...,"params":[...],"ts":...}` per call and blocks on `{"t":"tool_result","idx":N,"ok":...,"s":...}`, returning `s` (or a refusal text) as the per-call result; unknown-idx result → refuse loudly.

- [ ] **Step 1:** failing unit tests — host-mode `agent_execute_tool_calls` emits the request and returns the supplied `s` when a matching `tool_result` is fed to the reader; `ok:false` → refusal text; unknown idx → refusal. Non-host-mode path unchanged.
- [ ] **Step 2:** RED (`make -C external/ds4 ds4_agent_test`).
- [ ] **Step 3:** implement. `agent_stdin_read_line` reads one newline-terminated line from fd 0 (blocking; the worker thread may block). Emit via the existing `agent_emit_tool_event`-style NDJSON emitter (a new `tool_request` kind). Parse the result line's `idx`/`ok`/`s`.
- [ ] **Step 4:** GREEN + full `ds4_agent_test` green.
- [ ] **Step 5:** commit `agent: add --host-tools — tool_request/tool_result over the same pipe`.

### Task 2: Kit — parser + condenser

**Files:** `AgentWireParser.swift`, `ToolResultCondenser.swift` (new); tests.

**Interfaces:** `AgentEvent.toolRequest(idx: Int, name: String, params: [ToolParam])`; `ToolResultCondenser.condense(_ text: String, limit: Int = 8000) -> String` (deterministic: head + tail + a digest line when over limit); `TurnOutcome` gains `mutations: [String]`, `exitStatus: Int?`, `outputDigest: String?`, `validationRan: Bool` (defaulted).

- [ ] **Step 1:** failing tests. **Step 2:** RED. **Step 3:** implement. **Step 4:** GREEN. **Step 5:** commit `P9: parser toolRequest + ToolResultCondenser + outcome host facts`.

### Task 3: Kit — `FakeAppSource` + fake agent `--host-tools` mode

**Files:** `FakeAppSource.swift` (new), `FakeAgentSource.swift` (host-tools mode); tests.

**Interfaces:** `FakeAppSource.generate(answers: [String: String]) -> String` emits a fake app program: read `tool_request` lines, reply `tool_result` with the canned answer keyed by name (or `ok:false` when absent). The fake agent gains a `--host-tools` replay mode: on a `tool_request` block it emits the request and blocks on stdin for the result before continuing.

- [ ] **Step 1:** failing tests (determinism, canned-answer round trip in the harness). **Step 2:** RED. **Step 3:** implement. **Step 4:** GREEN. **Step 5:** commit `P9: FakeAppSource + fake agent host-tools mode`.

### Task 4: App — responder + controller routing

**Files:** `ToolCallbackResponder.swift` (new), `AgentController.swift`.

**Interfaces:** the controller, on `.toolRequest`, executes via the responder (consent-enforced, condenses via `ToolResultCondenser`, records host facts), writes the `tool_result` line to stdin, and feeds the facts into the open `TurnOutcomeBuilder`.

- [ ] **Step 1:** wire + a unit-testable pure `request→result` mapping. **Step 2:** RED. **Step 3:** implement. **Step 4:** `swift build` + `just test` green. **Step 5:** commit `P9: Agent tab answers tool calls over the wire`.

### Task 5: Integration — the round trip

**Files:** `ToolCallbackIntegrationTests.swift` (new); harness extension.

**Interfaces:** spawn fake agent (host-tools) + fake app connected by pipes; assert a tool block round-trips (request → canned result → agent continues), a refused result surfaces, and the responder records mutation/exit/digest.

- [ ] **Step 1:** failing integration test. **Step 2:** RED. **Step 3:** implement. **Step 4:** `just integration` green. **Step 5:** commit `P9: integration — tool-callback round trip`.

### Task 6: Recapture + close

- [ ] **Step 1:** `just test` + `just integration` + `make -C external/ds4 ds4_agent_test` green.
- [ ] **Step 2:** recapture `golden.ndjson`/`golden-tools.ndjson` at the new SHA (standing rule; the bare-CLI wire must be unchanged — the recapture proves it).
- [ ] **Step 3:** fork-ledger row #10 + json-events addendum (in the submodule, then gitlink bump).
- [ ] **Step 4:** verification record + ROADMAP (P9 complete, P10 next, concept budget **tool request**/**tool result**/**host tool execution**).
- [ ] **Step 5:** commit `P9: close — roadmap, concept budget, verification record`.
