# Roadmap

> **Planning surface, not the front door.** Where the current phase, deferred
> candidates, and the backlog live. Not where a new reader should start — see
> [`README.md`](README.md) for what this is, and [`BRIEF.md`](BRIEF.md) for
> the settled design.

*Phases group feature cycles. One direction at a time. Tangents go to the
Backlog, not into the current phase.*

## Now

A pointer, not a narrative — the detail lives in each phase's own row and its
linked docs. Update this list when what's in flight changes; do not grow it
into a second history of the phase table.

- **In flight / next:** P29, making the front-end honest — P29.9 (model picker), P29.1–P29.4 (honest session) and P29.10 (toolbar menus) done 2026-09-28/29; P29.5 next (spec [`2026-09-28-p29-5-fake-fidelity-design.md`](docs/superpowers/specs/2026-09-28-p29-5-fake-fidelity-design.md)). P28, the cut-over to ds4-engine, closed 2026-09-28 — see its row.
- **Closed with it:** the in-flight P24.4 cycle, P25 cycles 5–6, P18, the
  Mellum parking and the orchestrate-loop measurements all assumed machinery
  P28 removes; see the Backlog's "Closed or re-homed by P28".
- **Then, if wanted:** the Backlog's "Front-end" entries (Apply button,
  session picker).


## Phases

| # | Phase | Direction (one sentence) | Status |
|---|---|---|---|
| P0 | Scaffolding | Repository, docs toolchain, brief, roadmap, harvest briefs | **complete** |
| P1 | The fork, consolidated | One command builds `ds4-server` and `ds4-agent` from a pinned SHA on the shipped integration branch, with a ledger and a golden capture | complete (2026-08-22) *Removed in P28.* |
| P2 | It launches and answers | A regular macOS app with a real icon, a window, and a `Settings` scene starts the server and streams one chat turn — with the fast tier, the tripwire, and fake engines generated from P1's captures | complete (2026-08-22) *Window and Settings kept; server, fakes, fixtures replaced in P28.* |
| P3 | It can get its weights | Chunked parallel download with bitmap resume across restarts, and a launch that refuses infeasibly with an explanation a person can act on | complete (2026-08-22) *Removed in P28 (the engine admits memory).* |
| P4 | It shows what the machine is doing | Metrics tab: memory, GPU, CPU, power — led by **absolute** `ctx_used` and prefill throughput, on fixed-width, jitter-proof readouts | complete (2026-08-22) *Kept as per-pause, wire-only metrics in P28; host sampling removed.* |
| P5 | Capture is a program, not a lost file | `swiftstar-drive` committed, the capture format fixed, fixtures committed, the wire given a version handshake and timestamps | complete (2026-08-22) *Removed in P28.* |
| P6 | Diagnostics that can't lie | A deterministic analyzer over captures, with the model only phrasing the findings | complete (2026-08-22) *Removed in P28.* |
| P7 | Agent mode | Spawn `ds4-agent`, NDJSON transcript and capture-grade turn/tool outcomes, tool cards, workspace grant, shell toggle, interruptible turns | complete (2026-08-22) *Agent tab kept; `ds4-agent` wire replaced in P28.* |
| P8 | Skills | The Superpowers bootstrap through `-sys`, prefilled once into `sysprompt.kv`, with progressive disclosure | complete (2026-08-22) *Removed in P28.* |
| P9 | The tool-callback wire | SwiftStar answers tool calls over the same pipe — including a fake app side — and condenses tool results before they enter KV | complete (2026-08-22) *Removed in P28.* |
| P10 | Isolation | Worktree-isolated dispatch: a handoff packet in, a candidate ref or a receipt out | complete (2026-08-22) *Removed in P28.* |
| P11 | Subagent pool | Context-isolated subagents sharing one locked engine, ending at the plan's own measurement gate | complete (2026-08-23) *Removed in P28.* |
| P12 | Reliable agency | One model, three roles, host-owned structure: a typed packet per phase, bounded tools, real validation, and recovery — measured by writes and a passing acceptance suite, not tool calls | **complete (2026-08-25)** — all three roles evidenced live at least once (decompose closed the same day via P12.5); every number is small-n, none a reliability figure. P12.8's live phase-boundary confirmation and P12.0/P12.7 remain open, non-blocking items *Removed in P28.* |
| P13 | More models | Laguna XS 2.1 and/or Mellum 2.1 as first-class variants — **neither line has a shipping artifact yet**; deferred behind P12 so there is a harness that can actually evaluate a variant | complete (2026-08-25) — verdict: blocked on Mellum's tool-call **initiation** gate. **The broader "competence, not the harness" reading was overturned:** P15 found the action mode harness-addressable, and [P17](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md) found the multi-file repair failure was *predominantly a harness defect* (a directive asserting "exactly one file is wrong" on every cell) — with it removed, repair depth stops predicting failure and Mellum edits 15/17. The residual limit is authoring from an implied contract (1/6), not repair depth. Corrected 2026-08-27. **Corrected again 2026-08-29:** the "repair depth stops predicting failure" reading is overturned by the overnight campaign's Block B analysis — see [`2026-08-29-block-b-negative-result-analysis.md`](docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md) and P26 *Removed in P28.* |
| P14 | A docs site | Sphinx content and Pages publishing, once there is a reader who isn't the author | planned |
| P15 | Host-controlled action mode | The model drafts as text (`#path` + fenced blocks), the host harvests, writes, and verifies — isolating "should I act" from content competence for Mellum-class models; exit is a verdict, not a product | complete (2026-08-25) — verdict: **harness-addressable**; repair 4/4 at 13/13, build 3/9 at 13/13 with 0 tool calls *Removed in P28.* |
| P16 | Repair harness validity | Fix the four defects (round-discard, collection gate, packet budget, withheld phase brief) blocking any real measurement of Mellum's repair competence, driven by a validity-gated `/goal` loop | **demoted, not resumed** — superseded by P17's cheaper fixture-tier answer; `/goal` v1-v3 closed without meeting their goals, see [`goal-ledger.md`](docs/superpowers/research/goal-ledger.md) and [`goal-ledger-v3.md`](docs/superpowers/research/goal-ledger-v3.md) *Removed in P28.* |
| P17 | Repair-limit fixture experiment | Pre-registered fixture-tier experiment answering whether Mellum's multi-file repair failure is a budget, framing, or depth limit; then a follow-on attempt to optimise the repair loop itself | **complete (2026-08-26)** — verdict: predominantly a harness defect (a false "exactly one file" directive), not the model; Mellum 15/17 on editing tasks; the follow-on optimisation attempt (`/goal` v5) retired without a resolvable result — see [`2026-08-26-p17-repair-limit-verdict.md`](docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md) and [`goal-ledger-v5.md`](docs/superpowers/research/superseded/goal-ledger-v5.md). **Corrected 2026-08-29:** the 15/17 rate does not replicate on new data — see [`2026-08-29-block-b-negative-result-analysis.md`](docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md) and P26 *Removed in P28.* |
| P18 | `mellum-fixture` benchmark | A small, one-shot fixture benchmark for Mellum: one attempt, a flat 13-requirement oracle, frozen pre-registered manifest, no repair rounds, no self-modifying loop — separate from `swiftstar-agenttest` | **deferred to last (2026-08-27 decision)** — the benchmark runs after the model ladder and the remaining phases ship, validating the final state. **Job changed 2026-08-29:** P18 was scoped to *validate the final state* — implicitly to confirm a settled number. After the Block B overturn it is now the **arbiter of a contested one** (88% -> 68%, with a harness prompt fix landed mid-stream whose effect is unmeasured at real n). It also inherits an obligation nobody had written down: answering the depth question cleanly needs a **`depth-3-easy` fixture** (three files, three easy defects), because the existing `depth-3` uniquely contains the timezone trap, so the 95/63/44 profile is defect identity rather than file count — and no n fixes that. Mellum is INACTIVE until 2026-09-05, so this does not start before then. Design: [`2026-08-27-p18-mellum-fixture-design.md`](docs/superpowers/specs/2026-08-27-p18-mellum-fixture-design.md) *Removed in P28.* |
| P19 | One surface | The Agent is the app: Chat retired (the `ds4-server`/SSE path, `EngineController`, the tab), the ported Agent UI (composer, workspace picker, status bar + rings, message rendering, tool cards), Settings (shell toggle, font-size slider), per-turn summary on bubbles | **landed 2026-08-26** — Chat retirement `f546671`; UI port `ebfc046`; Settings `5d7c1de`; turn summary `8b9710b`; stop-button fix `478d871`. See the [`agent-surface-port verification record`](docs/superpowers/research/2026-08-26-agent-surface-port-verification-record.md) and the [`old-ui element inventory`](docs/2026-08-26-old-ui-element-inventory.md). Reopened and **complete 2026-08-27**: **P19.0** (consulted answer styling, stable-row-ID decision) and **P19.1** (the app shell) — a Tahoe-forward `NavigationSplitView` shell with a real customizable toolbar, collapsible sidebar, Settings moves (pool size, session capture, smart/dumb default, workspace default), one toolbar model choice with the engine lifecycle hidden, a component/region design vocabulary, and the Swift 6 concurrency gates. See the [`P19.1 design`](docs/superpowers/specs/2026-08-27-p19-1-app-shell-design.md) *UI kept; engine wiring replaced in P28.* |
| P20 | Delegation in one engine | Subagents without a second process: the app's agent spawns with `--subagent-pool N`; `/chat` (manual → pool-routed → answer surfaced); smart/dumb handoff-packet lever + dumb-mode dispatch refusal; restart-safe pool state | **Closed 2026-08-27** — live validation PASS (1 dispatch + 13/13, 695s, seed-dependent). [Closure verdict](docs/superpowers/research/2026-08-27-p20-closure-verdict.md); spec [2026-08-27-p20-orchestrate-loop-design.md](docs/superpowers/specs/2026-08-27-p20-orchestrate-loop-design.md).<br>**(1) `/orchestrate` coordination loop** (model-driven, one-shot-first per P17's no-repair-loop verdict) — `OrchestrateDirective.swift`, `orchestrate(task:writableFiles:)` replacing `orchestrateStub()`; needed engine divergence #12 (the `dispatch` schema).<br>**(2) Dispatch-preference bootstrap rule** — prefer dispatch once acceptance is machine-checkable; never for watched interactive sessions. [1809 findings](docs/superpowers/research/2026-08-27-1809-prefill-tail-findings.md).<br>**(3) Descoped:** small-ctx workers → P23; two-phase `/spike` → Backlog behind P24.<br>Commits: `00b5d80` `52257b8` `95ac5c3` `2011203` `53b7ee5` `3e07b54` `9efd050`. *Removed in P28.* |
| P21 | Measurable sessions | Telemetry you can act on: live session capture (wire + trace + stderr per spawn under `captures/live/`), the telemetry analyses (heavy-session compaction, spike shell-on findings) | **landed 2026-08-26** — capture `96fcc49`/`4e7cb3a`. See the [`heavy-session findings`](docs/superpowers/research/2026-08-26-heavy-session-telemetry-findings.md) and the [`spike shell-on findings`](docs/superpowers/research/2026-08-26-spike-shell-on-findings.md). Forward: the **DumbImplementer eval** (design around Σsuffix — Σprompt double-counts, so Σcached/Σprompt is not a cache-hit rate), and **expose the wire's `power` field** (already emitted; the parser drops it) as the first step toward the power question. The kind assertions and the DialLogic re-anchor landed 2026-08-27 — the fixture already carries kinds (no recapture needed), and the anchors are re-anchored to the app's 50k (25k/37.5k; critical now reachable). Which P19–P21 ideas have live evidence: the [`2026-08-26 evidence report`](docs/superpowers/research/2026-08-26-evidence-report.md) *Removed in P28.* |
| P22 | More models: Laguna XS + model switching | Laguna XS 2.1 as a first-class, choosable preset at parity with Laguna S — merge the unmerged `p13-laguna-xs-variant` branch (9 commits; its spec `2026-08-26-p13-laguna-xs-variant-design.md` lives on that branch), the completed live acceptance run, XS golden recapture — plus **model switching** (woven in): an "Apply this model" action that stops and re-spawns the agent with the new model, feasibility-/VariantGate-admitted *before* the stop (never kill a working session to switch to an infeasible model), transcript preserved, provenance per-spawn reflects the new model, pool re-spawns with it, switch refused mid-generation. XS is also the natural line for P20's small-ctx workers | **Closed.**<br>**(1) Laguna XS 2.1** — parity with Laguna S, merged 2026-08-27; live acceptance PASS, golden recapture. [Verdict](docs/superpowers/research/2026-08-27-p22-laguna-xs-acceptance-verdict.md), [recapture](docs/superpowers/research/2026-08-28-p22-xs-golden-recapture-verdict.md).<br>**(2) Model switching** ("Apply this model") — admission before stop; live-validated S→XS, an accidental XS→DeepSeek switch proved P25 Cycle 4b's admission denominator. [Verdict](docs/superpowers/research/2026-08-28-p22-model-switching-verdict.md) ([live](docs/superpowers/research/2026-08-28-p22-model-switching-live-validation.md)).<br>**(3) SSD streaming, Laguna line** — S resident at 20.53 GiB (~32.5 GiB saved); DFlash × SSD refused. [Verdict](docs/superpowers/research/2026-08-28-p22-ssd-across-the-line-verdict.md) ([live](docs/superpowers/research/2026-08-28-p22-ssd-across-the-line-live-validation.md)).<br>16 GB acceptance skipped by decision 2026-08-27, unconfirmed. *Gone: P28.* |
| P23 | Wire-level control | Per-turn think on the agent wire (`reasoning_effort`-style) **plus per-worker context for pool workers** (the small-ctx/RLM lever, descoped from P20 2026-08-27 and merged here). The think leg buys correctness and responsiveness — it bounds the observed think-to-the-wall failure and delivers the "fast reply"; its wall-clock ceiling is ~9.3%, so it is **not** a throughput lever. The per-worker-context leg carries the measured speed (4.2x prefill ceiling; ~6.15 GB → ~1.5 GB scratch per worker). One engine patch, **fork-ledger row #14** (P22's SSD widening took #13), one golden recapture. Spec: [`2026-08-28-p23-wire-level-control-design.md`](docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md) | **Implemented and closed 2026-08-28.** Spec: [design](docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md); full record: [wire-control research](docs/superpowers/research/2026-08-28-p23-wire-control-research.md).<br>**(1) Per-turn think** — `/quick`, `think_override` cap, `TurnThinkPolicy`; `TurnOutcome.sampler` records the effort actually used.<br>**(2) Per-worker context** — clamped to `[4096, parent]`, `sysprompt-<ctx>.kv`; fork-ledger row #14; golden recapture (also fixed a real ctx-swap data race and a stale `planned_bytes` drift, both traced in the research doc).<br>**Descoped:** warm-prefix routing (D11, stays Backlog); the "toolless" half of `/quick` (busts the KV prefix). **Deferred:** spec test 9 (think-to-the-wall regression) — no local model reproduces visible thinking; see the [repro attempt](docs/superpowers/research/2026-08-28-p23-think-to-the-wall-repro-attempt.md). *Removed in P28.* |
| P24 | Digested first-class tools | P9's deferred condensation-direction attack on prefill-tail cost (measured: one file re-read 31× = 37% of Σsuffix). Deterministic host-owned tools, in cycles: P24.1 windowed reads, P24.2 read-guard retirement, P24.3 run+digest tools, then P24.4 instrument reconciliation. `scout`, policy gating, and model-asks-human remain later ladder work. [Direction and re-scoping](docs/superpowers/research/2026-08-30-p24-direction-and-rescoping.md). | **(1) P24.1** — closed 2026-08-30; 799 tests; repeat rate 1.45→1.00. [Design](docs/superpowers/specs/2026-08-30-p24-1-window-honoring-reads-design.md), [measurement](docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md).<br>**(2) P24.2** — guard retired and `.pool` `readCache` removed; re-baselined. [Design](docs/superpowers/specs/2026-08-30-p24-2-read-guard-redecision-design.md).<br>**(3) P24.3 run+digest family** — landed on `main` 2026-08-30: host-owned `test`/`lint`, bounded `bash`, resolver, executor wiring, engine schemas, and tests. Golden recapture and paired-bill measurement remain outstanding.<br>**(4) P24.4** — next: reconcile the refusal-streak corrective and `toolCallBudget` timing between `swiftstar-agenttest` and the app. *Removed in P28.* |
| P27 | One eval CLI | `swiftstar-eval`: one CLI that runs an ad-hoc prompt, a `/quick` or the orchestrator through the app's own spawn path and hands every result to the same analyzer — replacing `swiftstar-drive` and `swiftstar-analyze`, with `swiftstar-agenttest` deferred to a second cycle | **CLI shipped 2026-08-31; the measurement it was built for has NOT run.** [Design](docs/superpowers/specs/2026-08-30-eval-cli-design.md), plans [1a](docs/superpowers/plans/2026-08-30-eval-cli-1a-kit-types.md) / [1b](docs/superpowers/plans/2026-08-30-eval-cli-1b-cli-and-extraction.md) / [1c](docs/superpowers/plans/2026-08-30-eval-cli-1c-the-bill.md).<br>**(1) The guard** — arms resolve to a full `SpawnRecord`; a run is refused when they differ by anything undeclared, or when the declared variable did not actually differ. Interleaved, seed-matched, no headline ratio.<br>**(2) The extraction** — the turn loop moved out of the 66 KB SwiftUI `AgentController` into a headless `AgentSession`; two source-text tests retired for behavioral ones.<br>**(3) Engine divergence #19** — `--tools`, cross-family.<br>**(4) Not done:** plan 1c (the P24.3 bill) and cycle 2. *Removed in P28.* |
| P28 | Cut over to ds4-engine | SwiftStar becomes a macOS front-end for one held `ds4-dogfood tui --ndjson` session — prompt, transcript, tool cards, per-pause metrics, stop, quit — and drops the forked C engine, host-run tools, pool, dispatch, model admission, SwiftStar-side captures and both eval CLIs | **complete (2026-09-28)** — hard cut-over; reopened `BRIEF.md` by owner direction. Spec [`2026-09-28-p28-ds4-engine-cutover-design.md`](docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md); plans [engine seam](docs/superpowers/plans/2026-09-28-p28-ds4-engine-cutover.md) and [app switch, removal, docs](docs/superpowers/plans/2026-09-28-p28-ds4-engine-cutover-app.md). No ds4 code, submodule or `ds4-agent` dialect remains; fast (68) and integration (11, fake `ds4-dogfood`) tiers green. Live, Laguna XS through `EngineSession`: `read` card with preview, answer, per-pause metrics, `/help` notice, Stop mid-turn, quit exit 0 with session dir and apply command; the built app spawns the exact argv and quits with no orphan (*idle only; quit mid-turn can orphan the engine, review A4 — P29.4*). GUI click-through not agent-verified (no screen access). |
| P29 | Make the front-end honest | Fix what the [P28 deep review](docs/superpowers/research/2026-09-28-p28-deep-review.md) found: session state, context gauge and dropped wire events that say something false, a quit that can outlive the app, a fake engine the tests over-trust — then shed dead weight and adopt macOS 26 SwiftUI idioms. Steps below | **in progress (2026-09-28)** — P29.9, P29.1–P29.4 and P29.10 done; P29.5–P29.8 open. From the review's ranked "do next"; steps in `## P29 steps`. |

## P29 steps

Source: [`2026-09-28-p28-deep-review.md`](docs/superpowers/research/2026-09-28-p28-deep-review.md)
(finding ids A/B/C below refer to it). Ordered by its ranked "do next".

1. **P29.1 Truthful session state.** *Done (2026-09-28).* Session state lives in Kit: `EngineSessionModel` (phase, transcript, metrics; applies events, exit and quit), `EngineSessionPhase` (with `quitting`, which counts as active), `EngineComposer` (can type / send / stop, label). Busy starts on the engine's `.prompt`, not on send; pending user rows read "Queued" and clear on the next `.prompt`, `.steering`, input, error or exit; exit clears everything; `EngineSessionError` is a `LocalizedError`. Fixes A1–A3. Tests include `busyClearsOnExit`, `stopDisabledWhileQueued`, `sendRefusedWhileQuitting`, `commandRowIsNotLeftPending`, `errorMidTurnKeepsStop`, `canSendWhileBusy`.
2. **P29.2 Context gauge by fraction.** *Done (2026-09-28).* `Severity.ofContext(used:size:)` in Kit — warning at 50 %, critical at 75 % of the engine's window (integer thresholds); the app's absolute thresholds are gone; BRIEF binding rule 1 now says the display is fractional and findings stay absolute. Fixes A5 (`twentyThousandWindowReachesCritical`).
3. **P29.3 Surface the dropped wire events.** *Done (2026-09-28).* Decoded and shown: `terminal` (outcome), empty answers (reason, else "the model stopped without answering"), `queued`, `steering_*`, `mentions` (attached / missing), `compacting` / `compacted` / `compact_failed`, `telemetry_error`, `clear` ("Conversation cleared"); metrics fold `session.context_size` and `interrupted.context_*`. After `ready`, an undecodable stdout line is a notice, not fatal (A7). Fixes A6, A7, A13. Payloads for the new events are hand-written from engine source — a fixture recapture is owed (P29.5).
4. **P29.4 Quit that ends a turn.** *Done (2026-09-28).* `EngineSession.quit()` is idempotent: mid-turn it writes `stop` and `quit` back to back (the relay takes quit before its queue), then SIGTERM after a stop grace and SIGKILL after a kill grace; the app holds `.terminateLater` until the engine exits (safety bound = the three graces + 5 s), and no start or restart runs once termination begins. Exits read "ended after the quit timed out", "ended by force after the quit timed out", "killed by signal N (NAME)" or "could not launch <path>: <reason>" (A12). Fixes A4 (`quitMidTurnEndsTheEngine` reaches SIGKILL). Live: quit mid-turn and during load both ended in about 0.5 s, no orphan.
5. **P29.5 Fake-engine fidelity and tests that can fail.** Make `fixtures/engine/fake-ds4-dogfood` queue prompts during a pause (`queued`), emit `stopping`, defer `quit` to the next `input`, refuse empty prompts and non-JSON as the relay does, and add a model-load gap after `ready`; drop or rewrite constant-echo tests; test `FAKE_ENGINE_EXIT` with the stderr tail. Why: B1, B2 (`EngineSessionTests.swift:187-203` proves bytes, not the queue contract). Done when: A2 is reproducible in the integration tier, and each B2-listed test either asserts a contract or is gone. Also B3 doc fixes (README Swift 6.2, glossary, provenance macOS 26). Also owed from P29.3: recapture fixtures containing `terminal`, `mentions`, `steering_*`, `telemetry_error`, `compact*` and `clear` (their tests use payloads written from engine source).
6. **P29.6 Stream and structure cleanup.** Replace `readabilityHandler` + `AsyncStream` + `LineBuffer` with `FileHandle.bytes.lines`; drop `FastTierGuard` (plugin and tool target) for one grep line in `just test`; rename `SwiftStarAppKit` to `SwiftStarEngine` (now including P29.10's `EngineModelCatalogLoader`); delete the B5 dead code (`PathAbbreviation.abbreviate`, `MarkdownPreprocess.fenced`/`language(forPath:)`, unread `EngineSessionInfo`/`outputTokens`/`resultKind`/`isAwaitingInput`/`interrupt()`, `ValueGaugeView.text`, `MetricsModel`, `fixedWidth`, `Tools/make-icon.swift`, `goal.md`, old-UI docs); rename `Agent*` views to `SessionView`/`PromptBubble`/`ToolCardView`; one `DefaultsKey` enum (covering `recentWorkspaces` and the `appShellInspectorPresented` key duplicated in `AgentView.swift` and `MainView.swift`); fix B6 stale comments; SwiftMath never renders (`deLaTeXed` strips math, `MarkdownText.swift:39-41`), so drop it or wire it. Why: C5–C8, B4–B7. Done when: build and both test tiers are green, `LineBuffer` and the plugin are gone, and no symbol in the B5 list is left without a caller.
7. **P29.7 SwiftUI modernisation.** Inject `EngineController` via `@Environment` and delete the `onChange` copy; composer's `TextField(axis: .vertical)` submits via `.onSubmit` instead of `.onKeyPress` (fixes A8); transcript with `.defaultScrollAnchor(.bottom)` and stable row ids; close-last-window quits plus `.restorationBehavior(.disabled)`; README "Build and run". Why: C9–C13, A8, A11 (`AgentView.swift:293-313`, `SwiftStarApp.swift:14`). Done when: owner GUI pass confirms Return submits, Option-Return newlines, and Cmd-W ends the engine.
8. **P29.8 Later (own cycle, not scheduled).** Native Markdown renderer replacing the pinned `MarkdownView` fork (C14), delta metrics from consecutive `checkpoint`s with the cumulative rate labelled "session avg" (C15, B3), Liquid Glass affordances (C16), plus C17–C20 and A9/A10 (apply command kept across sessions, first-launch workspace). Done when: each is either its own plan or declined.
9. **P29.9 Model picker: pass `--model-id`/`--context-size` to `ds4-dogfood tui`.** *Done (2026-09-28).* Settings has optional Model and Context size fields; the toolbar shows the loaded model and offers "Restart to use …" when Settings differ. Spec [`2026-09-28-p29-9-model-picker-design.md`](docs/superpowers/specs/2026-09-28-p29-9-model-picker-design.md). Live: `qwen3.8-flash-next` loaded from Settings alone; a bogus id is refused with the engine's reason. *Superseded by P29.10:* the Settings fields and "Restart to use …" are gone; the toolbar menus replace them.
10. **P29.10 Toolbar menus.** *Done (2026-09-29).* Folder, model and context are separate toolbar menu buttons (the sidebar toggle moved to the far right). The model menu lists the engine's models from `ds4-dogfood models --json` (ds4-engine TUI.35 on `main`; the Backlog's "Engine requests" closures explain the schema reconciliation), greying out models not on this Mac, too big, or not usable in the TUI; without the command it falls back and says why once. Choosing restarts the session; P29.9's Settings fields and Restart button are gone. Spec [`2026-09-29-p29-10-toolbar-menus-design.md`](docs/superpowers/specs/2026-09-29-p29-10-toolbar-menus-design.md).

Full done-when criteria live in each phase's own plan under
`docs/superpowers/plans/`, not restated here, to avoid drift between two copies.
Each plan is written as its phase begins. P12's plan is written:
[`2026-08-24-p12-reliable-agency.md`](docs/superpowers/plans/2026-08-24-p12-reliable-agency.md).
P13's design and benchmark record:
[`2026-08-25-p13-mellum-variant-design.md`](docs/superpowers/specs/2026-08-25-p13-mellum-variant-design.md),
[`2026-08-25-p13-mellum-benchmark-record.md`](docs/superpowers/research/2026-08-25-p13-mellum-benchmark-record.md).
P15's plan is archived at
[`2026-08-25-host-controlled-action-mode.md`](docs/superpowers/plans/archive/2026-08-25-host-controlled-action-mode.md).

### Dependencies worth knowing before planning

P28 removed the machinery the earlier planning notes here described (the
tool-callback wire, the pool, feasibility, the fork and its recapture rule).
They survive in version control at the commit before P28 and, in evidence
form, in `docs/superpowers/research/` and `docs/harvest/`. What still binds is
in `BRIEF.md`: the `ready` handshake, absolute `ctx_used`, fixtures recorded
from the real engine.


## Backlog

Deferred, each with the condition that reopens it. Grouped for scanning; a
group's order is not a priority order.

### Front-end

- **An Apply button.** The engine records edits in the session's
  `candidate.diff`; SwiftStar shows the session directory and
  `ds4-dogfood apply <id>` and applying stays a terminal step (P28 decision 4).
  *Reopens if copying that command out of the window becomes the daily friction,
  and ds4-engine exposes apply as a non-interactive machine-readable call.*
- **A session picker (`--continue`/`--resume`).** One session per launch today.
  *Reopens when a user wants yesterday's session back; needs ds4-engine's resume
  path to be reachable over `--ndjson`, which it currently refuses.*
- **Token streaming.** The protocol reports metrics per pause, not per token.
  *Upstream-bound: reopens only if ds4-engine adds live throughput to the wire.*
- **Packaging ds4-engine inside the `.app`.** The user installs it with
  `uv tool install`; SwiftStar finds it. *Reopens when a reader who is not the
  author needs to run the app without a terminal.*

- **Shell toggle (was the Agent tab's, then Settings').** Now an engine
  concern: shell and tool policy belong to ds4-engine. *Reopens only if
  ds4-engine exposes a spawn-time tool-policy flag worth a Settings control.*
- **A session browser.** Listing and searching past sessions, now over
  ds4-engine's `~/.local/state/ds4-engine/sessions/` rather than
  `~/.ds4/kvcache`. Same item as the session picker above.
- **P29.10's deferred minors.** A menu pick restarts the session even
  mid-turn, by design, but the select/restart path in `EngineController` has
  no automated test. The model list loads once per engine path, so an engine
  upgraded in place needs a relaunch. The catalog loader doesn't reap on
  timeout, has a small pid-reuse window before SIGKILL, and reads stderr's
  last line from only the first 4 KiB. *Reopens when P29.5's fake can drive
  a mid-turn restart, or if any of these is seen live.*

### Engine requests

Things SwiftStar cannot show or do until ds4-engine changes. Raise them there.

- **Rejected tool calls emit no event.** A call the engine refuses before
  running it (unknown tool, malformed, path refused) leaves no trace on the
  wire, so the front-end cannot show it (seen with Qwen3.8, 2026-09-28 and
  2026-09-29; research in ds4-engine
  `docs/superpowers/research/2026-09-28-qwen38-tool-calls.md`).
- **`/resume`, `/model`, `/rewind` re-exec in place.** They print to stdout
  and `execv` (same pid, a second `ready`); SwiftStar shows the printed lines
  as notices and ignores the second handshake, so it keeps the old session's
  model and state. Needs a wire message or a documented restart.

Closed, 2026-10-04 (caught up `../ds4-engine` to `main` at `409267a9`):
- **A `run` call ends the whole session** — fixed by ds4-engine TUI.45
  (`e592b0da`, citing SwiftStar #99 directly): under an interactive profile a
  `run` call is now answered as an unknown tool and the turn goes on.
- **A machine-readable model list** — shipped on ds4-engine `main` as TUI.35
  (`e5823e81`), not TUI.33 as first captured from the unmerged
  `feat/models-json` branch: the shipped shape sends no `schema_version`,
  `default_model_id`, `saved_model_id`, `family`, `measured_contexts` or
  `runs_in_tui`, and calls the context field `context` rather than
  `default_context`. `EngineModelCatalog.swift`'s decoder now treats a missing
  `schema_version` as 1 and falls back from `default_context` to `context`;
  `fixtures/engine/models-real.json` is recaptured from `main`. See
  `fixtures/engine/provenance.md`.

### Process and tooling

- **P6 has no verification record**, unlike P1–P5 and P7–P11. Not a defect in
  the phase — its analyzer and fixtures were committed and tested (P28 later
  removed them) — but the house convention is a record per closed phase, and
  P6's absence was only noticed during the 2026-08-25 P12 audit. *Reopens as
  cheap cleanup alongside another docs pass.*
- **A standing guard against under-specified authored prompts.** Four
  instances in one day on 2026-08-29 (P17's "exactly one file", a singular
  emission follow-up, a directive silent on ordering, a missing
  `projectContext`). Form is an open question — test, lint, or review step —
  and picking wrong yields something that gets disabled in three months.
- **Agent harness (Pi) tooling: lazy Context7 stays, Superpowers goes lazy.**
  The dev harness runs both as Pi packages (`npm:@upstash/context7-pi`,
  `git:github.com/obra/superpowers`). Context7 ships the right shape — two
  native tools plus a progressive-disclosure skill, ~160 tokens of description
  and nothing else until a library question matches. Superpowers is the
  outlier: `.pi/extensions/superpowers.ts` force-injects a ~1.1k-token
  bootstrap into the first run of every session and after each compaction,
  heavy on 8–16K windows (11–22% peak overhead). *Reopens as: a small
  Pi-harness work item — drop the bootstrap injection (a local extension, so it
  survives package reconciles), trim the skill list via a settings `skills`
  filter, optionally gate the rest with `disable-model-invocation` — validated
  by re-measuring system-prompt and first-run token cost on small-context
  models.* Source:
  [`2026-08-27-pi-harness-context7-superpowers.md`](docs/superpowers/research/2026-08-27-pi-harness-context7-superpowers.md).

### Closed or re-homed by P28

The pre-P28 Backlog assumed a forked engine and host-side machinery. Each group
is closed rather than annotated; the full entries survive in version control at
the commit before P28 (`git log -- ROADMAP.md`). Where an idea is still worth
having it belongs in ds4-engine's own backlog, not here.

- **Agent architecture and process** — the repair loop and its evidence
  coherence, harvest limits, `AGENTTEST_*` switches, specialized tool subagents,
  the dispatch decision, house style, the orchestrate directive, "Swift body,
  Python brain", the two-phase `/spike`. Closed: host tools,
  dispatch, repair and the agent-test CLI are removed. Agent policy is
  ds4-engine's.
- **Mellum inactive until 2026-09-05** — closed. Which model runs is the
  engine's choice; Mellum work, if it resumes, resumes there.
- **Pool and context economy** — small-ctx workers, context-economy tooling,
  `recall`, a compaction skeleton, RLM
  sub-queries, multi-project residency, snapshot/rewind, compare-before-commit,
  the admission scheduler, `.kv` replay fixtures, cross-session mining. Closed:
  there is no pool and no `.kv` handling in this repository. Re-homed to
  ds4-engine as engine features, unscheduled.
- **Model and engine features** — generation-time stopping, an engine-side
  memory-plan CLI, Laguna XS at 16 GB, `--null-model`, heterogeneous compute
  routing, grammar-constrained tool calls, DFlash, energy-aware pacing, an
  embedding spike. Closed here: all were engine changes carried by the fork.
  Re-homed to ds4-engine.
- **Evaluation and measurement** — test-tier reliability, the orchestrate 93%
  generalization arms, the failure-population and data-integrity flags,
  eval-system consolidation. Closed: `swiftstar-eval`, `swiftstar-agenttest`
  and their data went with P28. Evaluation lives in ds4-engine (`evals/`,
  `ds4-dogfood -p --json`).
- **ANE watcher tier** (a librarian and an inspector over Monty) — closed as a
  design note; it was a third tier beside the removed pool. It would re-enter as
  a new proposal against ds4-engine's tool surface.
- **Process and tooling** (closed part) — the duplicate golden fixtures, the
  fork branch name, parked `main.swift` items (a)–(c), the golden `kind`
  fixture, warm-started agent-test metrics. Closed: each named a removed file,
  the fork or the agent-test CLI. The `ROADMAP.md` size entry and the
  strict-docs-build failure are resolved (the Backlog is now short; the docs
  build is green). The engine-independent items (P6's verification record, the
  under-specified-prompts guard, Pi harness tooling) were kept in "Process and
  tooling" above; the shell toggle and session browser moved to "Front-end".
- **Retired earlier** — Chat as a separate surface (2026-08-26), phase-level
  recovery, `RepairLoop` receipt exits, workspace isolation and the handoff
  packet (P10): landed or retired, and their machinery removed.


### Declined

- **A menu-bar extra.** Explicitly declined 2026-08-21. *Reopens only on a
  direct request; the at-a-glance glance is the one thing it was good for.*

## Prior work

Completed phases P0-P15 are narrated in detail in [`docs/superpowers/research/prior-work-archive.md`](docs/superpowers/research/prior-work-archive.md); the phase table above and each phase's own verdict/closure doc carry the current status.

## Workflow

This repository runs on spec-driven development — see [`docs/sdd.md`](docs/sdd.md).
Each phase gets a committed design spec, then an implementation plan, then code.
The default test suite needs no model, no network, and no subprocess; process
behavior lives in a marked integration tier; and anything needing real weights
lives in a live tier that never runs in CI.
