# Harvest: the headless capture driver

**Recorded urgently, because this artifact has already been lost once and is
uncommitted again as of 2026-08-21.**

## Why this brief exists

The most valuable testing technique produced in the DS4 Control agent-mode work
was a headless driver that composes the app's production types without SwiftUI
and drives the *real* engine to produce genuine telemetry. It was built as a
throwaway test file, never committed, and deleted with its worktree. The only
durable output was a prose paragraph in the findings document. It was then
rebuilt from that paragraph — its own header describes it as a rebuild written
after the original source was gone — and is, again, uncommitted.

**SwiftStar's response is `swiftstar-drive`: a committed executable, not a test
file.** This brief records the contract to build it from. Under the clean-room
policy the code does not cross; the design and the interface do.

## Source

`Tests/DS4ControlTests/ZZTelemetryCaptureDriverTests.swift` in the
`feat/agent-mode-laguna` worktree of `~/projects/ds4-control` — 216 lines,
uncommitted. Its analysis was committed at `b7cc10a` as
`docs/superpowers/specs/2026-08-21-agent-telemetry-findings.md`; see
[telemetry-findings.md](telemetry-findings.md).

## What it does

Composes the same production types the SwiftUI composition root composes —
the process runner, the CPU/GPU/power/memory collectors, the agent memory
sampler, the NDJSON event parser, the telemetry log — directly, via
`@testable import`, with no SwiftUI involved. There is no GUI automation tool
in this environment, so this is the only way to exercise the real system.

It launches the real `ds4-agent --json-events` binary against real weights,
drives real prompts, and replays the metrics manager's exact collection logic
on a manual 2-second loop. **It is not new telemetry logic; it is the shipped
logic called directly.** That property is what makes its captures trustworthy,
and SwiftStar must preserve it: `swiftstar-drive` composes production types or
it is measuring something else.

## Interface contract

Gated so it never runs by accident: the run is skipped unless
`RUN_TELEMETRY_CAPTURE=1`. Invoked as
`RUN_TELEMETRY_CAPTURE=1 swift test --filter ZZTelemetryCaptureDriverTests`.

| Knob | Default | Purpose |
|---|---|---|
| `CAPTURE_CTX` | 150000 | Context size to launch with — the everyday setting |
| `CAPTURE_GGUF` | the Laguna S 2.1 gguf on disk | Absolute path to the weights |
| `CAPTURE_PROMPTS_FILE` | 3 built-in prompts | One prompt per line; how the dense-file-read methodology is reproduced |
| `CAPTURE_MODEL_LOAD_TIMEOUT` | 900s | Wait for the model to finish loading |
| `CAPTURE_TURN_TIMEOUT` | 900s | Wait for each turn |
| `CAPTURE_POWER` | unset | 1–99 power-limit percent, passed through at session start |
| `CAPTURE_PROGRESS_LOG` | a scratch path | Where live progress lines are written |

Output goes to the application-support telemetry directory as
`capture-<timestamp>-pid<pid>.jsonl`, in the same production telemetry format
the app itself writes. Live progress — model-load status, per-turn `ctx_used`
and prefill tok/s, the memory plan — streams to stdout *and* to the progress
log.

## Two bugs it had to solve, and why they are facts, not trivia

1. **The wire carries no timestamps.** Confirmed against
   `external/ds4/docs/json-events.md`. Partitioning wall-clock by state requires
   a wall-clock, so the driver stamps each NDJSON line with a receive time at
   the moment a complete line is assembled from the pipe, writing it to a
   sidecar `<name>.timestamps.jsonl` while keeping the raw NDJSON
   **byte-for-byte verbatim**. Pipe latency is sub-millisecond against
   multi-second states.
   *SwiftStar's response: put timestamps on the wire (P5) rather than
   perpetuate the sidecar. Keep the verbatim-raw rule regardless.*
2. **`swift test`'s relay of its `xctest` subprocess's stdout buffers in large
   chunks when redirected to a file**, even with `fflush(stdout)` in the driver.
   Progress was invisible for minutes while the agent was demonstrably alive.
   The fix was writing progress straight to a file the driver owns, bypassing
   the cross-process buffering.
   *SwiftStar's response: this is the clearest argument that the driver is a
   program, not a test. When you are routing around the test runner, you have
   outgrown it. The `ZZ` name prefix — a hack to control ordering within a
   suite — says the same thing.*

## A third fact, dearly bought

**The agent's `read` tool prefixes every line with its line number**
(`agent_read_range`, `ds4_agent.c:7222-7228`), so real token density is roughly
**19 tokens per line**, not the ~5 a prompt-sizing formula assumed. Getting this
wrong produced a 56,594-token prefill that overran a 300-second per-turn
timeout at 85% complete. Any workload script that sizes prompts by line count
needs this constant.

## What SwiftStar builds from this

`swiftstar-drive`, an executable target (phase P5):

- Composes production types directly. No `@testable`, because the types it
  needs are in `SwiftStarKit` and the app target by design.
- Writes a capture directory: raw wire verbatim, plus telemetry, plus its own
  progress log.
- **Is the source of every golden fixture from P5 onward.** Fakes are generated
  from its output, never hand-authored. P1's bootstrap captures predate it and
  are taken with a throwaway script under the same verbatim-raw rule; P5
  retires that script.
- Is run on every submodule bump, because a rebase can apply cleanly and still
  be semantically wrong.

**A known gap in any fixture set built this way:** compaction was never observed
at ctx 150,000 across two real attempts, only at 32,768. Fixtures will
over-represent the small-context regime unless a capture is aimed deliberately
at that gap.
