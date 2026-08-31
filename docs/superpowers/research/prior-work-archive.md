# ROADMAP's "Prior work" archive

Relocated verbatim from ROADMAP.md's `## Prior work` section on 2026-08-29
(the section had grown to ~300 lines narrating P0 through P15 a second time,
duplicating what the phase table's Status column and each phase's own
verdict/closure doc already say). Content unchanged except for relative
links, adjusted for this file's new location. See ROADMAP.md's phase table
for the current, terse status of each of these phases.

## Prior work

Completed phases move here when the roadmap outgrows the front page.

- **P0 — Scaffolding (2026-08-21).** Repository, `.gitignore`, license, docs
  toolchain (uv + Sphinx + MyST + Furo, `just docs` / `just watch-docs`), the
  `docs/superpowers/` structure, `BRIEF.md`, this file, and the harvest briefs.
  The design session that produced them, including the rejected alternatives and
  the adversarial review that corrected two of them, is recorded in
  [`../specs/2026-08-21-swiftstar-design.md`](../specs/2026-08-21-swiftstar-design.md).

- **P1 — The fork, consolidated (2026-08-22).** `pauleveritt/ds4` exists as a
  fork of `antirez/ds4`; the app-required patch set (`--json-events`,
  turn-interrupt, status marker, stale-interrupt latch, startup memory plan)
  is absorbed into one shipped integration branch; a documented command
  builds `ds4-server` and `ds4-agent` from the submodule; the fork ledger and
  `docs/upstream-proposals.md` are in place; two golden captures — SSE from
  `ds4-server`, NDJSON from `ds4-agent` — are taken from the real binaries by
  a throwaway line-stamping script (`swiftstar-drive` did not exist yet;
  P5 replaced the script and is the only sanctioned source of a fixture from
  P5 onward). Spec:
  [`../specs/2026-08-21-p1-fork-consolidated-design.md`](../specs/2026-08-21-p1-fork-consolidated-design.md).

- **P2 — It launches and answers (2026-08-22).** `SwiftStarKit` (pure: SSE
  parser, server argv builder, supervisor state machine, chat transcript
  reducer, fake-engine source generator) and `SwiftStar` (the SwiftUI app:
  five-tab window, working Chat tab, Settings scene on ⌘,) plus the fast tier
  (tripwire-guarded `swift test`) and the integration tier
  (`SWIFTSTAR_INTEGRATION=1 swift test`) with a fake `ds4-server` compiled from
  P1's `golden.sse`. The app auto-starts the real engine and streams SSE; two
  live-tier bugs the fake tier could not catch (the argv contract — `Process`
  prepends argv[0] — and the metal-source/CWD gotcha) were found and fixed.
  Spec: [`../specs/2026-08-22-p2-it-launches-and-answers-design.md`](../specs/2026-08-22-p2-it-launches-and-answers-design.md).

- **P3 — It can get its weights (2026-08-22).** A chunked parallel HTTP-Range
  downloader (`ChunkedDownload` + `DownloadBitmap`, resume-safe across
  restarts) and `Feasibility.check` — pure arithmetic on the engine's own
  `planned_bytes` from a real `ds4: memory:` boot line, refusing an
  infeasible launch with an actionable message rather than a percentage
  heuristic. Two real bugs found by the tests, not review: the range test
  server died on SIGPIPE and served the wrong byte range on an early client
  close; `SwiftStarAppKit` was split out of the app target because
  `@testable import SwiftStar` (an executable importing SwiftUI) fails to
  link — the download runner and its state moved to the testable library,
  the app stayed thin. *(Later correction, 2026-08-22: `Feasibility.check`'s
  design is right, but on Laguna the engine's own `planned_bytes` itself
  omits ~6.1 GB of per-session GPU scratch — see the P3 dependency bullet
  above and
  `./2026-08-22-p11-engine-constraints-and-corrections.md`.)*
  Spec: [`../specs/2026-08-22-p3-it-can-get-its-weights-design.md`](../specs/2026-08-22-p3-it-can-get-its-weights-design.md).

- **P4 — It shows what the machine is doing (2026-08-22).** `SwiftStarKit` gains
  the wire telemetry model (`WireEventParser` for NDJSON `status`/`ready`, the
  ratcheting `MetricsReducer`, and `DialLogic` — absolute context thresholds,
  generic memory thresholds, fixed-width formatting, sanitization) plus the
  `MachineSnapshot` type. `SwiftStarAppKit` gains `ProcessStatsCollector`
  (`proc_pid_rusage` footprint, `host_processor_info` CPU, `IOAccelerator` GPU,
  private `IOReport` watts — linked via `.linkedLibrary("IOReport")`) and
  `FixtureReplay` (bundled `golden.ndjson`). `SwiftStar` gains the `MetricsModel`
  + `MetricsView`, replacing the placeholder: a severity-colored context ring
  with a widened hit region, fixed-width Prompt/Decode readouts, and a
  capture-replay banner. The lead dials (`ctx_used`, throughput) are
  fixture-replayed until P7's agent migration; memory/GPU/CPU/power are live.
  Spec: [`../specs/2026-08-22-p4-it-shows-what-the-machine-is-doing-design.md`](../specs/2026-08-22-p4-it-shows-what-the-machine-is-doing-design.md).

- **P5 — Capture is a program, not a lost file (2026-08-22).** `swiftstar-drive`,
  a committed executable target, drives the real `ds4-agent` and writes the fixed
  capture format (`wire.ndjson` + `wire.stderr` + `wire.trace` + `provenance.md` +
  `progress.log`), byte-verbatim. Fork divergence #7 gives the `--json-events` wire
  a version/capability `hello` handshake (first line) and a monotonic `ts` on every
  event, retiring the P1 receive-time sidecar. `WireEventParser` enforces the
  handshake (refuses loudly on a mismatch) and reads `ts`; `CaptureWriter` (Kit)
  pins the format; fixtures are recaptured with the handshake + `trace` + `stderr`.
  The `--trace` channel (compaction rebuild stats) is now captured, which is what
  P6's "would compaction help" needs.
  Spec: [`../specs/2026-08-22-p5-capture-is-a-program-design.md`](../specs/2026-08-22-p5-capture-is-a-program-design.md).

- **P6 — Diagnostics that can't lie (2026-08-22).** `SwiftStarKit` gains
  `TraceParser` (parses the `--trace` channel: `compacted` rebuild stats and both
  `prefill sync done` shapes), `DiagnosticsLogic` (baseline/current prefill
  extraction, degradation and cache-health bands, all re-anchorable constants),
  the typed `Finding`/`CompactionVerdict` model, `DeterministicPhraser` (the
  "compute vs. phrase" seam — a model phraser can replace it later), and
  `DiagnosticsAnalyzer`, which computes the BRIEF's first job deterministically:
  where you are in context, current prefill throughput, drift off your own
  session's baseline, and — deep *and* degraded — whether compaction would help
  (distinguishing "cache healthy → won't fix the rate" from "cache missing → may
  recover"). The Diagnostics tab replaces its placeholder with a fixture-driven
  list of findings. Evidence floor met: the analyzer accepts the real `golden`
  capture and rejects a committed synthetic `pathological` fixture reproducing
  the measured 7x curve. No live engine, no model, no engine patch.
  Spec: [`../specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md`](../specs/2026-08-22-p6-diagnostics-that-cant-lie-design.md).

- **P7 — Agent mode (2026-08-22).** The Agent tab is real. `SwiftStarKit`
  gains `AgentWireParser` (the NDJSON transcript parser — `hello`/`status`/
  `ready`/`text`/`think`/`tool`/`queued`, handshake-enforced, with the `ready`
  turn-outcome fields), `AgentTranscript` (the tool-card reducer — one card per
  call, keyed by block-scoped `idx`; the `tool` phase appends, `param_end`/
  `output`/`finish` mutate in place), `TurnOutcome`/`TurnOutcomeBuilder` (D12's
  capture-grade per-turn record — model/build/sampler + task, token/context use,
  stop reason, tool-call lifecycles), and `AgentCommand` (the one argv contract —
  `--workspace` + `--shell`). `SwiftStar` gains `AgentController` (spawns
  `ds4-agent`, drains the wire → transcript, writes ETX on interrupt, builds one
  `TurnOutcome` per turn) and `AgentView` (the transcript with tool cards, the
  composer, the interrupt button, the consent controls). The engine
  (`ds4_agent.c`) gains `--workspace` (cwd + file-tool confinement — fail closed)
  and `--shell` (gate `bash` in schema + dispatch), plus the turn-end `ready`
  fields (`stop_reason`/`generated`/`ctx_used`, D12). Two fixtures: `golden.ndjson`
  recaptured at the new SHA, `golden-tools.ndjson` new — five tool blocks
  (`read`/`list`/`write`/`edit`/`bash`) whose five turn-end `ready` events each
  carry `stop_reason`. The fake `ds4-agent` is generated from the real capture,
  never hand-authored. Evidence floor met: the fixture yields turn outcomes with
  the full tool lifecycle and a typed stop reason; the fake validates the exact
  argv and honors ETX. Live Metrics/Diagnostics wiring deferred (D9 — see the P4
  bullet's dated correction).
  Spec: [`../specs/2026-08-22-p7-agent-mode-design.md`](../specs/2026-08-22-p7-agent-mode-design.md).

- **P8 — Skills (2026-08-22).** The Superpowers bootstrap is real. `SwiftStarKit`
  gains `SuperpowersBootstrap` — a deterministic index rendered from a skills
  dir (`name`/`description` front-matter, sorted by name, with a generic
  disclosure path), passed to the agent via `AgentCommand`'s new
  `systemPrompt: String?` → `-sys <text>` (appended after `--shell`).
  `SwiftStarAppKit` gains `SkillStager` — a recursive `FileManager` copy of the
  skills tree into `<workspace>/.swiftstar/skills/` at spawn, idempotent
  (removes a pre-existing destination), throwing on a missing skills dir
  (non-fatal degrade). `AgentController` resolves the skills dir
  (`SUPERPOWERS_SKILLS_DIR` else the default), stages (a throw logged and
  non-fatal), builds the bootstrap, and sets `settings.systemPrompt` before the
  spawn argv is built — so the fake's strict-argv validation carries the same
  deterministic bootstrap. Progressive disclosure: the index names skills; the
  agent `read`s each body on demand inside the workspace grant (D5 — never
  fabricate a dispatch call). No engine patch (D4 — `sysprompt.kv` already
  rebuilds on mismatch). Evidence floor met: the bootstrap names every skill;
  the staged workspace contains them; the fake's expected argv carries the
  bootstrap it validates.
  Spec: [`../specs/2026-08-22-p8-skills-design.md`](../specs/2026-08-22-p8-skills-design.md).

- **P9 — The tool-callback wire (2026-08-22).** The host owns tool execution.
  The engine's `--host-tools` flag (fork divergence #10) makes
  `agent_execute_tool_calls` emit one `tool_request` per call on stdout and block
  on a matching `tool_result` from stdin (the worker thread owns the blocking
  read, gated by `host_tool_reading` so the UI thread's prompt poll does not
  steal the result line); a mismatched `idx` or any non-`tool_result` line is a
  loud refusal. `hello` advertises `"tool_request"` in `caps` iff the flag is
  set. `SwiftStarKit` gains `.toolRequest` on `AgentWireParser`, a pure
  `ToolResultCondenser` (cap 8000, deterministic digest), and
  `ToolCallbackResponder` (the consent matrix — file tools proceed inside the
  workspace, escapes refuse, `bash` is shell-gated, web tools always refuse —
  plus execution and the condensed `tool_result` line); `FakeAppSource` is the
  fake app side (keyed canned answers + the fixed refusal). `AgentController`
  routes `tool_request` → responder → `tool_result` over stdin and records the
  host facts into the per-turn `TurnOutcome`. The round trip is
  `FakeHostToolsIntegrationTests` (a fake agent compiled from `golden-tools.ndjson`
  with `hostTools:true` ↔ a fake app; the agent emits one request per block,
  blocks, the app answers, the agent continues to `eos`; `ok:false` still
  continues). The live recapture at `c21b831` re-verified the bare wire is
  unchanged (D1: `tool_request`-free, observation-only) and caught a real defect —
  the `741f722` edit dropped the `"]"` closing the `hello` `caps` array, emitting
  invalid JSON the wire consumer refused; the `c21b831` amend closes it and adds
  `test_agent_emit_hello_caps_array_closes` (red-then-green). Spec:
  [`../specs/2026-08-22-p9-tool-callback-wire-design.md`](../specs/2026-08-22-p9-tool-callback-wire-design.md).

- **P10 — Isolation (2026-08-22).** A dispatched attempt is isolated.
  `SwiftStarKit` gains `HandoffPacket` (`taskText`, `writableFiles` exact and
  worktree-relative, `validationCommand`, per-file `FileBaseline` baselines —
  `sha256` + `lineEnding` + Unix `mode` read from the worktree, never guessed —
  and turn/tool-call budgets), `DispatchOutcome` (`.candidate(ref:turnOutcome:)`
  | `.receipt(Receipt)`; `Receipt` = `.refusedTool`/`.budgetExceeded`/
  `.validationFailed(exit:digest:)`/`.noChanges`), and the pure
  `WorktreeDispatch.verdict` — the `request → verdict` mapping (revision check →
  budget → validation → `noChanges` → candidate) plus `relativize` (strip the
  worktree prefix so the verdict compares worktree-relative forms against
  `writableFiles`). `SwiftStarAppKit` gains `WorktreeDispatcher.dispatch` (creates
  a disposable worktree on a throwaway branch, reads baselines, runs the
  validation command parent-side, commits the diff, returns the ref; the worktree
  + branch are removed in `defer`, the commit object survives so the ref
  resolves). `SwiftStar` gains the dispatched-attempt entry in `AgentController` —
  a fresh, ephemeral `ds4-agent` at `--workspace <worktree>` with shell off and
  host-tools on, the P9 responder revision-checking each mutation against
  `packet.writableFiles` (an out-of-set `write`/`edit` is refused host-side, not
  executed, not recorded), the finished `TurnOutcome` relativized to the worktree
  before the pure verdict — and a minimal Dispatch tab. The caller's tree is
  never touched; nothing merges. Evidence floor met: the candidate ref is a real
  commit that resolves via `git rev-parse` after the worktree is removed; a
  changed file differs from its baseline; a refused tool / exceeded budget /
  failed validation / no changes each yields a typed receipt. No live end-to-end
  dispatch (the app target has no test target; the pure pieces the dispatch
  routes through are tier-tested; a real-model dispatch is out of scope for the
  tiered oracles). No new wire — the dispatch reuses P9's `--host-tools` spawn.
  Spec: [`../specs/2026-08-22-p10-isolation-design.md`](../specs/2026-08-22-p10-isolation-design.md).

- **P11 — Subagent pool (2026-08-23).** Context-isolated subagents share one
  locked engine. The engine patch (`--subagent-pool`, fork divergence #11) hosts
  N sessions in one process on one model load, multiplexes a `worker` id on every
  `--json-events` event (absent when N==1, so the single-session wire is
  byte-identical — the recapture proved it), advertises a `pool` cap, and routes
  inbound `{"t":"prompt","worker":N,"s":"..."}` prompts by worker; generation is
  serialized by a pool mutex around `worker_run_turn` (and around worker init,
  whose concurrent system-prompt prefill segfaulted the first live run — a Metal
  command-buffer race caught only by the live smoke gate). `SwiftStarKit` gains
  the wire-contract layer — `WorkerId`/`PoolWireParser`/`PoolPrompt`/
  `DispatchReceipt` (+ the reserved `DispatchExecutor`), the pure `PoolScheduler`
  (enqueue/start/finish/fail/inject), the `RollingDigest` reducer, `ContextAssembly`
  (deterministic adaptation in v1; the no-think model trip is deferred with the
  RLM tier), `EnvelopeMath` + deterministic perturbation constructors, and
  `DispatchPacketBuilder`. `SwiftStarAppKit` gains `PoolEngine` (spawn argv,
  `.kv` reader, `listFiles`). The app gains the `dispatch` host-tool, the
  dispatch→queue→worker-turn→receipt-injection loop, and the smoke-gate driver.
  The measurement gate's canonical arm is measured: **3.70x realized win vs the
  4.2x ceiling** (deep 131k 1550 s vs 8×16k pool 419 s; overhead ratio 0.88) —
  the sensitivity envelope (bloat/failure/count-sweep) is the follow-up pass.
  Live evidence:
  [`smoke gate`](./2026-08-23-p11-smoke-gate.md),
  [`measurement gate`](./2026-08-23-p11-measurement-gate.md).
  Spec: [`../specs/2026-08-23-p11-subagent-pool-design.md`](../specs/2026-08-23-p11-subagent-pool-design.md).

- **P12 — Reliable agency (2026-08-25).** Reframed 2026-08-24 from "More
  models" after an overnight investigation found the blocker was model
  *agency*, not model *variety*: a local model that writes correct code still
  fails to reliably act, and the failures traced to host-side contract and
  prompt shape more often than to the model. One model runs a
  role-differentiated pipeline — decompose, implement, repair — with the host
  owning phase boundaries, budgets, permissions, validation, and recovery.
  **Complete (2026-08-25) — all three roles evidenced live, each at small
  n; not a reliability claim.** What shipped: P12.1 hardened the packet
  validator/parser (schema version, CRLF, block-scalar, comment-stripping
  fixes) and wired `thinkBudget` and path presentation as a real lever;
  P12.2 made the Mellum Q5_0 quant loadable; P12.3 ran the prompt-shape
  ablation for Laguna (absolute paths a real lever, n=3, real grading);
  P12.4 added the repair role (fixture tier 3/3 ×2, plus two live
  non-fixture repairs reaching 13/13, n=2); P12.5 ran live the same day —
  a model-authored decompose packet set matched a hand-authored baseline's
  phase count, orphaned nothing, passed validation, and drove the run to
  the same final result, n=1; P12.6 met the second half of its own
  disjunctive criterion by naming and classifying the next failure mode
  (*completes-and-is-wrong*, not shallow exploration); P12.7 shipped its
  first 2 of 5 pieces the same night — trace-channel capture and
  Σprompt/Σcached/Σsuffix, live-confirmed; P12.8 wired phase-level recovery,
  plus a same-night fix (`953d05a`) so a failed repair now retries with
  fresh evidence instead of exiting immediately.
  What did **not** ship, and is not claimed: **P12.0's source-of-truth
  document was never written** and no superseded-doc banners were applied —
  `2026-08-24-overnight-consolidation.md` still stands as unmerged staging;
  **P12.7 shipped 2 of 5 pieces the same night** — trace-channel capture
  and Σprompt/Σcached/Σsuffix, live-confirmed (`20260825-232102-roadmap`:
  38014/33828/4186); no `DumbImplementer`, no stateful tokens (deliberately
  deferred), no warm-started timing, no `docs/cool_things/` write-up —
  **the `DumbImplementer` packet shape later shipped via P20's dumb lever**
  (`DispatchPacketBuilder(dumb: true)`, `2011203`/`53b7ee5`);
  P12.3's Mellum arm never ran; P12.4's live
  end-to-end tier (three phases → 13/13 from packets, at any real n) was
  started and stopped, so beyond those two n=2 instances the evidence is
  fixture-tier only; P12.8's own live phase-boundary confirmation
  specifically (a `validationFailed` receipt mid-build, retried) has not
  recurred since the fix landed — four live attempts since have hit either
  a clean pass or a `noChanges`/eos phase followed by an end-of-run
  acceptance failure (P12.4's repair, not P12.8's), never the mid-build
  validation failure P12.8 targets.
  **Reopen condition P12.5: met 2026-08-25.** Same pattern as P13's verdict
  naming its own reopen condition (which became P15), except this one
  closed the same day rather than opening a new sub-phase. An earlier
  version of this entry claimed P12.0 and P12.7 shipped; both claims were
  false and were corrected 2026-08-25 after an audit.
  Verdict: [`2026-08-25-p12-verdict-record.md`](./2026-08-25-p12-verdict-record.md).
  P12.0's deliverable, landed late and at reduced scope:
  [`2026-08-25-local-model-agency.md`](./2026-08-25-local-model-agency.md).
  Plan: [`2026-08-24-p12-reliable-agency.md`](../plans/2026-08-24-p12-reliable-agency.md).

- **P13 — More models (2026-08-25).** Mellum 2.1 wired as a first-class
  `Variant` (memory-gated, contract-enforced admission before any engine
  spawn) and benchmarked live against P12's harness: path presentation × nudge
  × seed, at Mellum's published sampler (temp 0.6, top-k 20, top-p 0.95,
  min-p 0.0 — not a hostile setting). **Verdict: the competence gate fails —
  Mellum reliably fails the tool-call initiation gate under the tested
  harness** (0 tool calls across every cell of the 2×2, seed-swept). This
  blocks shipping Mellum as a preset; it is not a claim that Mellum's agent
  competence fails in the absolute, and the variant plumbing itself is
  complete and correct. The verdict named its own reopen condition — the
  out-of-phase host-controlled action mode — which became P15. Design:
  [`2026-08-25-p13-mellum-variant-design.md`](../specs/2026-08-25-p13-mellum-variant-design.md).
  Benchmark record:
  [`2026-08-25-p13-mellum-benchmark-record.md`](./2026-08-25-p13-mellum-benchmark-record.md).

- **P15 — Host-controlled action mode (2026-08-25).** Asked whether Mellum is
  **harness-addressable** (a host-side fix reaches it) or content-broken, by
  removing tool initiation from the loop: the model emits `#path` headings plus
  file bodies as text, `LabeledBlockParser` harvests them, the host writes the
  files and injects the paths into `TurnOutcome.mutations`, then validates and
  grades as usual. **Verdict: harness-addressable.** Every failure mode the
  phase found was host-side and each yielded to a host-side fix — a two-turn
  emission protocol for turns that reason and then stop; a lenient harvest for
  bodies emitted without fences; first-occurrence-wins plus a repeated-heading
  abort for degenerate resampling; and captured validation output for failures
  that previously recorded only an exit status. No engine work, no sampler
  change, no different model.

  Measured: repair **4/4 at 13/13**; build **3/9 at 13/13**, all three phases,
  **0 tool calls** — 85–128s for the run that happens to pass, but the failed
  attempts along the way cost wall-clock too: summed across all 9 sequential
  runs, **≈4.7 minutes per completed app**. All nine build runs harvested (0
  `contractNotFollowed`, previously 3 of 4). The phase's own bar asks for a
  host-verified candidate with content-bucketed failures and explicitly defers
  any per-model pass-rate guarantee, so 3-of-9 is a recorded measurement rather
  than a missed bar — and it is emphatically **not** a claim of reliability.

  Two numbers were retracted inside the phase after re-reading primary evidence:
  the build arm's "1/4" was a parser artifact, and an early "3/5" did not
  survive a larger sample. All results carry the in-band `resultClass` label
  **"drafting quality + host orchestration, not agency"** — 0 tool calls means
  the model never acted and the host wrote every file. Design:
  [`2026-08-25-host-controlled-action-mode-design.md`](../specs/2026-08-25-host-controlled-action-mode-design.md).
  Plan:
  [`2026-08-25-host-controlled-action-mode.md`](../plans/archive/2026-08-25-host-controlled-action-mode.md).
  Verdict record:
  [`2026-08-25-p15-verdict-record.md`](./2026-08-25-p15-verdict-record.md).
  Review:
  [`2026-08-25-p15-fable-review.md`](./2026-08-25-p15-fable-review.md).
