# SwiftStar P2 design: it launches and answers

**Date:** 2026-08-22
**Status:** approved by delegation (overnight work; the human partner pre-authorized
"work unattended and use your recommendations for spec and plan"). The phase list and
architecture are settled by `BRIEF.md` / `ROADMAP.md` / `2026-08-21-swiftstar-design.md`.
**Phase:** P2 — It launches and answers.

This spec is the authority on *how* P2 is done. It does not reopen the phase list, the
architecture, or the engine seam. The project-level why lives in `BRIEF.md`.

## Problem

SwiftStar is a repository of documents. Nothing launches. P1 proved the engine builds and
captured its two wires; P2's job is to prove the *product* shape: a regular macOS app that
spawns `ds4-server`, streams one chat turn over SSE, and does it with a test tier that is
fast, honest, and mechanically guarded. This is the phase that creates the three-target
split (`SwiftStarKit` / `SwiftStar` / test tiers) that every later phase depends on, and the
tripwire that keeps the fast tier fast.

## The wire P2 consumes: SSE from `ds4-server`

Source of truth: `fixtures/server/golden.sse` (P1 first capture, canonical =
`golden.sse`, the house-puzzle request). Facts gardenable from it, each with a fixture
citation:

- The stream is `data: {json}\n` chunks separated by blank lines, ending with a
  `data: [DONE]` line as the final non-blank line.
- First chunk: `{"id":"chatcmpl-2","object":"chat.completion.chunk","created":<epoch>,
  "model":"laguna-s-2.1","choices":[{"index":0,"delta":{"role":"assistant"},
  "finish_reason":null}]}`.
- Reasoning tokens arrive as `"delta":{"reasoning_content":"<token>"}`; answer tokens as
  `"delta":{"content":"<token>"}`; the final data chunk carries `"finish_reason":"stop"`.
- `id` is constant within a request and increments per request served by the process
  (`chatcmpl-1` then `chatcmpl-2` across the two P1 captures). `created` is epoch seconds
  at emit time, advancing ~once per second across a stream — **not** a constant request
  epoch (unlike OpenAI's SSE shape). Both facts recorded in
  `fixtures/server/provenance.md`.
- The wire has **no version handshake** until P5 (binding rule 7 in `BRIEF.md`). A P2
  parser must parse this shape and must **not** refuse a stream that lacks a handshake.

## Decisions

### D1 — Three SwiftPM targets plus two test targets; swift-testing

`Package.swift` with Swift 6 language mode, `platforms: [.macOS(.v26)]`, targets:

| Target | Role | Rules |
|---|---|---|
| `SwiftStarKit` | Pure logic: SSE parser, server command builder, supervisor state machine, fake-engine source generator | No SwiftUI, no IOKit, no `Foundation.Process`, no network. Functions of their inputs. |
| `SwiftStar` | The app: scenes, `Process` spawning, pipes, the chat view model, Settings, icon/bundle | Thin; decisions live in Kit |
| `SwiftStarKitTests` | Fast tier | swift-testing; scanned by the tripwire; fixtures only |
| `SwiftStarIntegrationTests` | Integration tier (marked) | Real `Process`, real files, fake engine binaries; gated behind `SWIFTSTAR_INTEGRATION=1` |

**Rejected:** a single test target for both tiers — the tripwire cannot distinguish
fast from marked if they share a target; and XCTest — `BRIEF.md` mandates swift-testing.

### D2 — Test-tier gating: env-gated suites, not build-time selection

Integration suites are annotated `.enabled(if: ProcessInfo.processInfo.environment
["SWIFTSTAR_INTEGRATION"] == "1")`. Default `swift test` compiles both test targets but
runs only the fast suites; `just integration` sets the env var and runs everything. The
tripwire scans only `SwiftStarKitTests` sources, so the integration target's legitimate
`Process` use never trips it.

### D3 — The tripwire: a build-time static guard on the fast tier

A SwiftPM build tool plugin (`FastTierGuard`) applied to the `SwiftStarKitTests` target
scans its Swift sources for a forbidden-symbol list — `Process(`, `URLSession`,
`NWConnection`, `Network`, `Darwin`, `posix_spawn`, `socket(`, `exec(` — and fails the
build naming `file:line`. This is the brief's "tripwire that fails the build when a
default-tier test spawns a process or opens a socket," implemented as a static guard.

Documented limits (in the plugin's own comment and here): it is a drift alarm, not a
sandbox — a test could in principle dodge the scan via stringly indirection. The fast
tier is additionally structurally safe because `SwiftStarKit` has no `Process`/network
API to reach, and fast tests depend only on Kit. When the scan's symbol list needs to
change, the change lands with a test that demonstrates the tripwire firing (see plan
Task 2).

### D4 — SSE parser in Kit: streaming, forward-compatible, refuses nothing it can ignore

`SSEEvent` (enum): `.role(assistant)`, `.reasoning(String)`, `.content(String)`,
`.finish(.stop)`, `.done`, `.ignored(String)` (any line that is not a parseable
`data: {json}` chunk or that carries fields the parser does not model). The parser is a
streaming line consumer: given the next wire line it either emits an event or nothing.
Unknown JSON fields inside a chunk are preserved under `.ignored` — the wire can grow
fields at P5/P6 and this parser will not refuse them. No handshake is required or
refused (binding rule 7).

Tested against the literal bytes of `fixtures/server/golden.sse` and
`golden.short.sse`: the full sequence must match the fixture's documented shape.

### D5 — Server command builder in Kit: one argv contract

`EngineSettings` (engineDir, modelPath, contextSize, port, host) and
`ServerCommand.argv` produce the exact argv the app passes to `Process`:

```
[-m, <modelPath>, -c, <contextSize>, --host, 127.0.0.1, --port, <port>]
```

**Correction (2026-08-22, recorded per the SDD retraction convention):** the
original contract included `<engineDir>/ds4-server` as the first element. That
was wrong: `Process` prepends the executable path as argv[0] itself, so the
real engine received its own path as an unknown option. The fake engine
validated the same wrong contract self-consistently, so the integration tier
could not catch it — the live smoke against the real binary did
(`ds4-server: unknown option: …/ds4-server`). The binary path now lives in
`ServerCommand.binaryPath(settings:)`; `Process` is spawned with
`executableURL` = binary path and `arguments` = the array above.

This is the argv the fake engine validates strictly (D7) and the argv the app uses for the
real engine. `engineDir` defaults to `DS4_DIR` or the submodule path
(`external/ds4`); `contextSize` default 32768 (the P1 capture's setting).

### D6 — Supervisor state machine in Kit: a pure transition function

`SupervisorState` (enum): `.stopped`, `.starting`, `.ready`, `.generating`, `.stopping`,
`.failed(EngineFailure)`. `EngineFailure` is a small value type: `.engineMissing(URL)`,
`.portInUse(Int)`, `.instanceLocked`, `.exited(code: Int32)`, `.stderr(EngineStderr)`,
`.timeout`. `supervise(_ state: SupervisorState, _ event: SupervisorEvent) ->
SupervisorState` is a pure function; `SupervisorEvent` covers `.launchRequested`,
`.engineMissing(URL)`, `.stdoutLine`, `.stderrLine(String)`, `.generationStarted`,
`.generationFinished`, `.exit(Int32)`, `.stopRequested`, `.timeoutFired`. (Plan
amendment: `.readyLine` was dropped — ds4-server announces readiness on **stderr** as
`listening on http://…`, so readiness is classified inside `.stderrLine` handling; the
two generation events were added for chat turns; `.engineMissing(URL)` lets the app report
a missing binary without making policy.) All decisions (which transitions are legal, what
a stderr line means) are here, tested in milliseconds. The app holds the state and
forwards events; it never makes policy.

**Gardened fact (from P1, `fixtures/agent/provenance.md` gotcha #2 and the live run):**
`ds4-server` enforces a single-instance lock (`/tmp/ds4.lock`, override
`DS4_LOCK_FILE`). Launching a second instance fails with `another ds4 process is already
running (pid N)` on stderr. The supervisor must map that stderr line to `.instanceLocked`
and the app must say so, rather than looping. The app will also probe a free port before
launch (`.portInUse` remains for races).

### D7 — Fake engine: generated from the capture, never hand-authored, argv-strict

`FakeServerSource.generate(capture: Data, sidecar: Data, engineArgv: [String]) -> String`
(pure, in Kit) emits the complete Swift source of a fake `ds4-server` executable that:

1. Validates its argv **strictly** against the expected engine argv; on any mismatch it
   prints a one-line explanation to stderr and exits 1.
2. Listens on `--port` and, per accepted connection, replays the capture's `data:` lines
   with inter-line delays derived from the sidecar's receive times.
3. Reads an optional `FAKE_SPEED` env var (a multiplier; `0` = no delay) so integration
   tests are seconds, not minutes. Env is not argv — argv stays strict.

Two structural properties make this honest (brief, "Testing"): the fake is *produced from*
the committed capture, so a rebase that changes the emitter changes the fake and the
parser together — no hand-authored co-drift; and the generator is deterministic, pinned
by a fast-tier test that regenerates and asserts byte-identical output.

The integration tier compiles the generated source with `swiftc` into a temp binary,
spawns it with the launcher's exact argv, connects a TCP client, runs the Kit SSE parser
over the stream, and asserts the event sequence matches the capture. A sibling test spawns
it with wrong argv and asserts refusal (exit 1 + stderr message).

### D8 — The app: a regular windowed macOS application

`SwiftStar` is an `@main` SwiftUI app: `WindowGroup` with a `TabView` of the five tabs —
Chat, Agent, Metrics, Diagnostics, Help — where Agent/Metrics/Diagnostics/Help are
placeholder screens stating which phase they arrive in (P7/P4/P6). A `Settings` scene on
⌘, with one pane, **Engine**: engineDir, modelPath, contextSize, port, plus a "Pick…"
file chooser for the model. Defaults: `DS4_DIR` (else `external/ds4`), the P1 weights path,
32768, and a free port probed at launch.

The Chat tab is the P2 surface: an engine status line driven by the supervisor state, a
transcript, and a composer. Send starts the engine if needed (spawn via
`ServerCommand.argv`, stdout pipe → `SSEParser` → transcript), streams token deltas as
they arrive, and shows `.reasoning` in a dimmed style and `.content` as the answer.
Stop terminates the child (SIGTERM). Engine stderr is captured and the last line is shown
in the status area on failure.

The app is built into a real bundle: `just app` compiles, assembles
`.build/SwiftStar.app` with a generated `Info.plist` and `AppIcon.icns`, and the app sets
`.regular` activation policy. A committed icon-generation script (`Tools/make-icon.swift`)
renders the AppIcon (a simple star glyph) with AppKit and `iconutil`; the generated
`.icns` is committed so the bundle build is deterministic.

### D9 — Scope discipline

P2 does **not** ship: Agent mode (P7), Metrics (P4), Diagnostics (P6), downloads (P3),
`swiftstar-drive` (P5), the NDJSON parser (P7), the wire handshake (P5), or more than one
Settings pane. Chat is one streaming turn per send; no session history persistence, no
tool calls (the observation-only wire), no compaction controls.

## Done when

1. `just test` (fast tier) is green in seconds — parser, command builder, supervisor
   transitions, generator determinism/refusal — running only committed fixtures, with no
   process spawn and no socket (tripwire-gated).
2. The tripwire is real: a deliberately added fast-tier test referencing `Process(` makes
   the build fail with the plugin's message, and removing it restores green (recorded in
   the plan execution).
3. `just integration` (`SWIFTSTAR_INTEGRATION=1 swift test`) is green: the fake engine
   compiled from `golden.sse`, launched with the exact launcher argv, stream parsed, event
   sequence matches the capture; wrong argv refused.
4. `just app` produces a runnable `SwiftStar.app` with icon, window, five tabs, a working
   Chat tab, and a `Settings` scene on ⌘, with the Engine pane.
5. Live smoke (manual, not CI): with `DS4_DIR` pointing at the submodule, the app starts
   the real `ds4-server` against the P1 weights and streams one chat turn.
6. Every new test has been shown to fail first, then pass (binding rule 2), and no test
   asserts on source text (binding rule 3). Refusal tests have sibling success tests
   (binding rule 4).
7. `ROADMAP.md` marks P2 complete; the concept budget is reviewed (terms that earned
   their place this phase: **wire**, **capture**, **fixture**, **seam** — definitions
   land in the glossary section of the plan).
