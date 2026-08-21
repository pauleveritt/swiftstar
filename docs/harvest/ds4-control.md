# Harvest: DS4 Control

**Source:** `~/projects/ds4-control` — a macOS menu-bar control pane for a local
DeepSeek V4 / Laguna S 2.1 engine. ~41 Swift source files, ~28 test files, and a
design trail across six worktrees. It works; it is being retired.

**This is evidence, not source.** Code does not cross. The facts below cross
only with the citation attached and a fresh test written here.

## Shipped features, and what each one earned

| Feature | Where it lived | The fact worth keeping |
|---|---|---|
| Process supervision | `SupervisorService`, `ProcessRunner`, `ReadinessMatcher` | Readiness is detected from **stderr strings**, not from a port becoming open; health polling and crash detection are separate concerns with distinct edge cases |
| Weight download | `HFDownloader`, `ChunkFetcher`, `ChunkBitmap`, `DownloadProbe` | Parallel chunked download with **offset writes plus an on-disk bitmap sidecar**, so a resume survives an app restart mid-chunk, not merely a paused download |
| Memory feasibility | `Feasibility`, `Variant` | Mirrors the pinned engine's **Metal context allocator**, the shared graph-workspace formula, and persistent backend-scratch bounds; gates a launch against the **wired limit** |
| SSD streaming | `feat/ssd-streaming` | The wired-limit gate must charge **resident weights, not the full GGUF**, when experts stream from disk |
| Metrics | `Metrics/*`, `IOReportBridge` | Power and frequency come from **private IOReport**; the channel and subgroup keys were found empirically |
| Chat | `ChatService`, `ChatSSEParser`, `MarkdownText` | `content` is the answer and `reasoning_content` is thinking; they are separate streams on one SSE connection |
| Agent mode | `AgentSession`, `AgentEventParser`, `AgentEvent` | NDJSON on stdout with `text`/`think`/`tool`/`status`/`ready`/`queued`; prompts arrive on **stdin**, submitted after 200ms of quiet |
| Telemetry | `TelemetryLog`, `AgentProcessMemory` | Per-session telemetry to disk; per-pid memory attribution via `proc_pid_rusage`, verified against `ps` |
| Agent launcher | `AgentLauncher` | Opening a terminal agent against the local server is a wrapper script plus `osascript`, not a library call |

## Gardened facts, with citations to fetch before transplanting

Each of these must be re-fetched from its source at transplant time, not copied
from this table. **The preview-weights caveat applies to all of the numeric
ones:** the current GGUFs are preview artifacts, and their sizes, allocator
formulas, and memory tiers must be re-read against the pinned engine revision
before a GA release — never carried forward unchanged.

- **Metal context-allocation formula, shared graph-workspace formula, persistent
  backend-scratch bounds.** Cite the ds4 revision pinned by the submodule.
- **Exact GGUF byte sizes, `ctxCeiling` per variant, and the `thinkMax`
  threshold of 393,216.** Cite the variant definition and the weights.
- **IOReport channel and subgroup keys** for power and frequency. Empirical;
  cite the collector that found them.
- **Readiness stderr strings.** Cite the engine's emitting source, not the
  matcher — the matcher is downstream of the truth.
- **`read` prefixes line numbers**, giving ~19 tokens/line
  (`agent_read_range`, `ds4_agent.c:7222-7228`). See
  [capture-driver.md](capture-driver.md).
- **The wire carries no timestamps**
  (`external/ds4/docs/json-events.md`). SwiftStar fixes this rather than
  inheriting it.

## Incidents to re-earn deliberately

Carry each as a sentence in the phase that needs it. Do not transplant the test.

- **Download resume must survive a restart mid-chunk.** The old repo's
  `DownloadRaceTests` is why.
- **The wired-limit gate must be SSD-streaming-aware.** Charging the full GGUF
  when experts stream from disk refuses launches that would have worked.
- **A saved expert-cache budget above the current quant produced a negative
  freed-RAM caption.** Clamp at zero.
- **A stale agent memory plan leaked across sessions.** Clear it when a new
  session starts.
- **Chat scroll froze under streaming markdown.** The state machine, not the
  view, was the cause.

## The design trail worth reading before planning a phase

Twelve plans and thirteen specs live under
`docs/superpowers/{plans,specs}/` in the `feat/agent-mode-laguna` worktree, plus
one research note. The ones with the most transferable content:

- `2026-08-19-agent-mode-foundations.md` and `-walking-skeleton.md` — how agent
  mode was brought up, including the spike that found **zero ANSI bytes** on
  stdout because every escape-emitting call site is `isatty`-gated.
- `2026-08-20-agent-json-events.md` — the wire's design and its golden-fixture
  discipline.
- `2026-08-21-agent-telemetry.md` and its findings — see
  [telemetry-findings.md](telemetry-findings.md).
- `2026-08-21-agent-subagent-pool.md` — SwiftStar's P11, already written and
  independently reviewed.
- `research/2026-08-21-skills-for-ds4-agent.md` — SwiftStar's P8. See below.

## The skills research, which becomes P8

The engine turns out to be an unusually good host for a skills bootstrap,
because features built for KV economy are exactly what progressive disclosure
needs:

- **`sysprompt.kv` prefills the bootstrap once, ever.** The rendered system and
  tool prompt is checkpointed as a KV cache file and restored from disk on every
  later session start. Claude Code, Pi, and every hosted harness re-process
  their bootstrap every session; this one does not.
- **Compaction rebuilds *from* the system prompt**, so the bootstrap survives
  compaction structurally. No re-injection hook is needed — unlike the Pi
  extension, which must subscribe to compaction and re-arm.
- **Bounded `read` plus `more`** makes progressive disclosure native, and a
  skill read cannot blow the context.
- **The 50K reminder cycle** provides mid-session re-assertion for free.

The non-negotiable requirement is **automatic session-start injection with no
per-session opt-in**. Everything else degrades gracefully; subagent dispatch in
particular has sanctioned fallback wording, and **must never be faked**.

The acceptance test is specific and should be inherited verbatim: in a clean
session, "Let's make a react todo list" must auto-trigger the brainstorming
skill *before any code is written*, with a captured transcript.

**The caveat the research states about itself:** every artifact in both
predecessor repositories was produced through other harnesses, never through
this engine. The corpus proves the methodology produces good work. It proves
nothing about this harness or this model.
