# P5 — Capture Is a Program, Not a Lost File: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the throwaway capture script with a committed `swiftstar-drive` executable, fix the capture format (wire + stderr + trace + provenance), give the `--json-events` wire a version handshake and per-event timestamps, and recapture the fixtures.

**Architecture:** A new engine patch (fork divergence #7) emits a `hello` handshake first and a monotonic `ts` on every event. `swiftstar-drive` (new executable target) composes `WireEventParser`, drives the real `ds4-agent`, and writes a byte-verbatim capture directory. `WireEventParser` gains handshake enforcement and `ts`. Fixtures are recaptured with the patched binary.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing; C for the engine patch; no Sphinx changes.

**Spec:** `docs/superpowers/specs/2026-08-22-p5-capture-is-a-program-design.md`

## Global Constraints

- Fast tier (`just test`): no model, no network, no subprocess (tripwire-scanned).
- Live tier (`just capture`): the real engine + real weights; never in CI; takes minutes.
- Binding rules: every new test shown to fail first; no source-text assertions; fakes are generated from captures, never hand-authored.
- Verbatim-raw rule: the wire/stderr/trace are stored byte-for-byte; nothing is reformatted.
- Every submodule bump owes a recapture (now including the handshake).
- **Ordering note:** the old parser ignores `hello`/`ts` (unknown `t` / extra field), so the engine patch lands *before* the parser change with no broken window. Recapture (Task 3) precedes parser enforcement (Task 4).

---

### Task 1: Engine patch — handshake + timestamps (fork divergence #7)

**Files:**
- Modify: `external/ds4/ds4_agent.c` (5 emitters + handshake + helper), `external/ds4/docs/json-events.md` (document the new fields), `external/ds4/docs/fork-ledger.md` (divergence #7), `external/ds4/docs/upstream-proposals.md` (extend proposal #1)

**Interfaces:**
- Produces: first NDJSON line `{"t":"hello","v":1,"caps":[…],"ts":<µs>}`; every event gains `,"ts":<µs>` (monotonic, `clock_gettime(CLOCK_MONOTONIC)`).

- [ ] **Step 1: Add the timestamp helper** (near `agent_emit_event_str`, ds4_agent.c ~:4697):

```c
/* Monotonic microseconds since engine start, on every json-events line. */
static void agent_buf_put_ts(agent_buf *b, const agent_worker *w) {
    (void)w;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    unsigned long long us = (unsigned long long)ts.tv_sec * 1000000ULL
                          + (unsigned long long)(ts.tv_nsec / 1000);
    char num[32];
    snprintf(num, sizeof(num), ",\"ts\":%llu", us);
    agent_buf_puts(b, num);
}
```

- [ ] **Step 2: Add the handshake emitter** (beside the helper):

```c
/* Version/capability handshake: the first line when --json-events is active. */
static void agent_emit_hello(agent_worker *w) {
    agent_buf b = {0};
    agent_buf_puts(&b, "{\"t\":\"hello\",\"v\":1,\"caps\":[\"status\",\"ready\","
                       "\"text\",\"think\",\"tool\",\"queued\",\"ts\"]");
    agent_buf_put_ts(&b, w);
    agent_buf_puts(&b, "}\n");
    char *line = agent_buf_take(&b);
    if (line) { agent_publish_raw(w, line, strlen(line)); free(line); }
}
```

- [ ] **Step 3: Call `agent_buf_put_ts(&b, w)` in all five emitters, immediately before the closing `"}\n"`.** In `agent_emit_event_str`, `agent_emit_tool_event`, `agent_emit_bare_event`, `agent_emit_ready_event`, and `agent_emit_status_event`, the final field sequence becomes `…agent_buf_puts(&b, "\""); agent_buf_put_ts(&b, w); agent_buf_puts(&b, "}\n");`. (For the numeric-only emitters the closing `"}` becomes `agent_buf_put_ts(&b, w); agent_buf_puts(&b, "}\n");` after their last field.)

- [ ] **Step 4: Emit the handshake once at worker start.** In the `--json-events` non-interactive startup path (where `w->out` is first serviced / `run_agent_non_interactive` begins), call `agent_emit_hello(w)` before any `ready`/`status` emission — after the worker exists with `json_events` set. If there is a single "worker created + json_events" site, call it there; otherwise call it at the top of the non-interactive loop guarded by `w->cfg->json_events`.

- [ ] **Step 5: Rebuild and smoke.** `just engine`; then run a one-shot `ds4-agent --json-events --non-interactive -p "hi" -m <gguf>` and confirm stdout begins with `{"t":"hello",…}` and each event carries `ts`. (Live — needs the real weights; the pause for a clear machine applies here.)

- [ ] **Step 6: Document.** `json-events.md`: add the `hello` event and the `ts` field (on every event). `fork-ledger.md`: add divergence #7 ("wire handshake + per-event timestamps", retires when upstream lands structured events with a version/timestamp). `upstream-proposals.md`: extend proposal #1's "suggested upstream shape" to mention the handshake + `ts`.

- [ ] **Step 7: Commit** — `git commit -m "P5: wire handshake + per-event timestamps (fork divergence #7)"`

---

### Task 2: `swiftstar-drive` executable + capture format

**Files:**
- Modify: `Package.swift` (add the executable target)
- Create: `Sources/swiftstar-drive/main.swift`, `Sources/SwiftStarKit/CaptureWriter.swift` (the format, pure + testable), `Tests/SwiftStarIntegrationTests/CaptureWriterTests.swift`

**Interfaces:**
- Produces: `CaptureWriter.write(directory:wire:stderr:trace:manifest:) throws` (writes the five files byte-verbatim; `manifest` is a struct with `submoduleSHA`, `commandLine`, `model`, `ctx`, `startedAt`); the `swiftstar-drive` executable (env knobs `CAPTURE_GGUF`, `CAPTURE_CTX`, `CAPTURE_PROMPTS_FILE`, `CAPTURE_MODEL_LOAD_TIMEOUT`, `CAPTURE_TURN_TIMEOUT`, `CAPTURE_PROGRESS_LOG`).

- [ ] **Step 1: Add the target** in `Package.swift`:

```swift
.executableTarget(name: "swiftstar-drive", dependencies: ["SwiftStarKit"]),
```

- [ ] **Step 2: `CaptureWriter` (Kit, pure)** — writes the directory and the five files; the wire/stderr/trace bytes are written exactly as given, provenance is rendered from the manifest. Tested in Task 2's integration test (write to a temp dir, assert byte-identical files and the manifest's contents).

- [ ] **Step 3: `main.swift`** — the driver: build the argv (model, ctx, `--json-events --non-interactive --trace <dir>/wire.trace`), set the P1 env (`DS4_METAL_*_SOURCE`, `DS4_LOCK_FILE`), spawn with stdin/stdout/stderr as pipes, tee stdout→`wire.ndjson` + parse `ready` events via `WireEventParser`, tee stderr→`wire.stderr`, write `provenance.md` and `progress.log`. Feed prompts one at a time (write line to stdin, wait for the `ready`-event count to advance before the next). On completion, close stdin and stop the engine.

- [ ] **Step 4: Build** — `swift build` green.

- [ ] **Step 5: Shown-fail (integration)** — in `CaptureWriter`, write the wire file from the stderr bytes; the byte-identity assertion fails; restore; green.

- [ ] **Step 6: Commit** — `git commit -m "P5: swiftstar-drive + capture format"`

---

### Task 3: Recapture the fixtures (live tier)

**Files:**
- Modify: `fixtures/agent/golden.ndjson`, `fixtures/agent/provenance.md`
- Create: `fixtures/agent/golden.trace`, `fixtures/agent/golden.stderr`
- Delete: `fixtures/agent/golden.ndjson.sidecar`

- [ ] **Step 1:** `just engine`, then `CAPTURE_GGUF=<p1 model> CAPTURE_CTX=32768 just capture` to produce a capture directory.

- [ ] **Step 2:** Copy `wire.ndjson`→`golden.ndjson`, `wire.trace`→`golden.trace`, `wire.stderr`→`golden.stderr`, and merge the capture provenance into `fixtures/agent/provenance.md` (handshake + ts noted; SHA re-confirmed). Delete the sidecar.

- [ ] **Step 3:** Verify the new fixture: first non-blank line is `{"t":"hello",…}`; `status` events carry `ts`; the trace contains the boot/turn trace lines; `git diff` shows the wire is byte-for-byte the engine's output.

- [ ] **Step 4: Commit** — `git commit -m "P5: recapture fixtures with handshake + trace + stderr"`

---

### Task 4: Parser enforces the handshake + reads `ts` (Kit)

**Files:**
- Modify: `Sources/SwiftStarKit/WireEventParser.swift`, `Tests/SwiftStarKitTests/WireEventParserTests.swift`

**Interfaces:**
- Produces: `WireEvent.hello(version: Int, capabilities: [String])`, `WireEvent.refused(String)`, `StatusSnapshot.ts: UInt64`.

- [ ] **Step 1: Write the failing tests.** New cases: `helloParsesHandshake`, `firstNonBlankLineMustBeHandshake` (a status line first → `.refused`), `unknownVersionRefuses` (`v:99` → `.refused`), `missingRequiredCapRefuses` (hello without `ts` cap → `.refused`), `statusCarriesTs`. Update every existing test that feeds an event without a handshake to feed `{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":0}` first; update `StatusSnapshot(...)` constructions with `ts:`.

- [ ] **Step 2: Run to verify failure** — build/assertion errors.

- [ ] **Step 3: Implement** — add `private var sawHandshake = false`; on the first non-blank line enforce `t:"hello"` + `v == 1` + required caps (`status`, `ready`, `ts`), emitting `.hello`/`.refused`; parse `ts` into `StatusSnapshot`; existing events otherwise unchanged.

- [ ] **Step 4: Run to verify pass** — `just test` green against the recaptured fixture (Task 3).

- [ ] **Step 5: Shown-fail** — flip `v == 1` to `v == 2`; `helloParsesHandshake`/`firstNonBlankLineMustBeHandshake` fail; restore; green.

- [ ] **Step 6: Commit** — `git commit -m "P5: parser enforces handshake + reads ts (Kit)"`

---

### Task 5: ROADMAP close + verification record

**Files:**
- Modify: `ROADMAP.md` (P5 → complete; Prior work entry; concept budget: **handshake**, **trace**)
- Create: `docs/superpowers/research/2026-08-22-p5-verification-record.md`

- [ ] **Step 1: Verification record** — fast-tier counts + shown-fail records, the live capture evidence (handshake first line, ts on events, trace captured), and the engine-patch notes.

- [ ] **Step 2: ROADMAP** — P5 row → `complete (2026-08-22)`; Prior work entry; concept budget definitions for **handshake** and **trace**; note the recapture rule now includes the handshake.

- [ ] **Step 3: Final gates** — `just test`, `just integration`, `just docs` green; tree clean.

- [ ] **Step 4: Commit** — `git commit -m "P5: close — roadmap, concept budget, verification record"`

---

## Self-Review

**Spec coverage:** D1 driver (T2), D2 format (T2), D3 handshake+ts patch (T1), D4 parser (T4), D5 recapture (T3), D6 scope (no tasks for telemetry-to-disk, ds4-server capture, or CI automation). Done-when 1→T1, 2→T2, 3→T4, 4→T3, 5→T5.

**Placeholder scan:** the C patch names the exact emitters and the helper; `main.swift` is described step-by-step (the driver is written by the executor, who is driving a real engine, so its full body is inlined at execution rather than reproduced here). No TBDs.

**Type consistency:** `hello`/`refused`/`ts` (T4) used by T2's driver (the `ready`-count watch) and T3's fixture verification. `CaptureWriter` (T2) is the only new Kit type.

**Sequencing:** engine patch (T1) → driver (T2) → recapture (T3) → parser enforcement (T4) → close (T5). The old parser ignores `hello`/`ts`, so T1 does not break the pre-P5 tests; recapture precedes parser enforcement so the fixture tests stay green.

**Live-tier gate:** Tasks 1 (smoke) and 3 (recapture) need the real engine + weights and a machine with no other `ds4` instance holding the lock — the reason this plan pauses before implementation.
