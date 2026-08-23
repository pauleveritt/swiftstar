# `golden-tools.ndjson` — capture notes (P9 recapture; P7 tool-event fixture)

This fixture is a **verbatim, byte-for-byte copy of `ds4-agent`'s stdout** from one real
`--json-events` session that exercises the full file/shell tool zoo, captured by the committed
`swiftstar-drive` program (P5 driver, P7 consent knobs). Nothing was hand-written or
reformatted. It is the live-tier counterpart to `golden.ndjson`: where `golden` re-verifies the
wire contract (handshake, `ts`, status/ready shape) over two text-only turns, `golden-tools`
proves the wire carries the **tool-phase zoo** (`read`/`write`/`edit`/`list`/`bash`), the
**block `start`/`tool`/`param_*`/`finish`** sequence, a bash **`output`** event, and — added by
the P7 submodule bump (divergence #9 / D12) — a **`stop_reason`/`generated`/`ctx_used`** on every
turn-end `ready`. Task 7's outcome-telemetry tests depend on this fixture carrying those fields.
The P9 recapture (submodule `c21b831`) re-verifies the zoo against the rebuilt binary; the
`--host-tools` flag (divergence #10) is off here — the engine executes the tools internally and
emits the **observation-only** `tool` phase stream (no `tool_request`) — so this fixture is
unchanged in shape. The `--host-tools`-on **round trip** (the host answers `tool_request` over
stdin) is proven by `FakeHostToolsIntegrationTests`, not by this live capture (the driver cannot
answer `tool_request`); see
`docs/superpowers/research/2026-08-22-p9-verification-record.md`.

## Provenance

- Submodule (`external/ds4`) SHA: `c21b8319866c2ac625d0c1dab7dc2d0aa75aee18`
  (the P9 bump — `--host-tools` tool-callback wire (divergence #10); off here, so the engine
  executes internally and this fixture is the observation-only `tool` phase stream. The P7
  consent flags `--workspace`/`--shell` (divergence #8) and turn-outcome `ready` fields
  `stop_reason`/`generated`/`ctx_used` (divergence #9 / D12) are intact. The SwiftStar gitlink
  pins this exact SHA; the P7 capture was at `35bf505`.)
- Built with: `just engine` (`make -C external/ds4 ds4-agent`). Binary run in place,
  `external/ds4/ds4-agent`.
- Captured by: `swiftstar-drive`, run from the repo root with
  `CAPTURE_GGUF=$HOME/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf \
   CAPTURE_WORKSPACE=/tmp/swiftstar-p9-workspace CAPTURE_SHELL=on \
   CAPTURE_PROMPTS_FILE=Tools/p7-tool-capture-prompts.txt just capture`.
- Model file: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (Laguna S 2.1, 48 GiB) at
  `~/projects/ds4/gguf/`.
- Recorded command line (from the capture's `CaptureManifest.commandLine`):
  `external/ds4/ds4-agent -m <gguf> -c 32768 --metal --non-interactive --json-events \
   --trace <capture-dir>/wire.trace --workspace /tmp/swiftstar-p9-workspace --shell on`
- `DS4_LOCK_FILE=/tmp/ds4-capture-<pid>.lock`.
- Wall-clock start: `2026-08-23T05:27:09Z`; handshake `ts` anchor: `328097177680`.

## Workspace + the `--workspace` chdir / Metal-source interaction

The engine's `--workspace DIR` consent flag (divergence #8) sets the agent's cwd to the
workspace (it reuses the existing `--chdir` site in `main`), and `agent_confine_path` resolves
every tool path against that cwd, refusing anything that escapes the workspace root
(fail-closed). So `seed.txt`, `.`, and the bash `command` all resolve relative to the workspace.

Workspace setup before capture:

```bash
mkdir -p /tmp/swiftstar-p9-workspace && rm -f /tmp/swiftstar-p9-workspace/seed.txt
```

**Metal-source override (driver behavior, recorded for reproducibility).** The engine's Metal
loader reads its kernels cwd-relative (`metal/<k>.metal`) — it tries the `DS4_METAL_*_SOURCE`
env override, then `metal/<k>.metal`, then `./metal/<k>.metal`, all against the cwd. With
`--workspace` the engine `chdir`s into `/tmp/swiftstar-p9-workspace`, where there is no `metal/`
dir, so a bare capture aborts with `ds4: Metal source metal/flash_attn.metal not found … metal
backend unavailable; aborting startup` (verified: the first probe failed exactly there). The
engine sanctions the per-source `DS4_METAL_*_SOURCE` override for exactly this ("a diagnostic run
can swap one source file"). `swiftstar-drive`, **when `CAPTURE_WORKSPACE` is set**, enumerates
`external/ds4/metal/*.metal` and sets each `DS4_METAL_<STEM>_SOURCE` to its absolute path, so
Metal resolves regardless of the post-`chdir` cwd. The P5 shape (no `CAPTURE_WORKSPACE`) sets no
such env vars and keeps cwd at `external/ds4`, so `golden.ndjson` is unaffected.

## Prompts sent, in order

From `Tools/p7-tool-capture-prompts.txt` (one per line; each is a single-line instruction chosen
to induce a tool call with machine-independent paths/output):

1. `Write a file named seed.txt in the current directory with content exactly: hello from golden-tools`
2. `Read the file seed.txt`
3. `Edit seed.txt: replace the text "hello" with "hi"`
4. `List the current directory`
5. `Run the command: echo hello-world`

**Stability rationale.** The workspace is the engine's cwd, so every tool path is relative
(`seed.txt`, `.`); `write`/`edit`/`read`/`list` carry the relative path verbatim and the bash
`output` event echoes the literal `hello-world\n`. No absolute paths, no `pwd`/`ls /tmp`, so the
fixture is reproducible on any machine that runs the capture from a clone with the submodule at
`c21b831` (the only machine-specific bits — the absolute model path and the `DS4_METAL_*_SOURCE`
overrides — are not on the wire).

## Step 4 verification (against the real `ds4-agent` at `c21b831`)

Greps over the captured `wire.ndjson` (`captures/20260823-012657-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf/`):

| grep | count | requirement |
|---|---:|---|
| `"phase":"start"`  | 5 | ≥ 1 (a block opens before each tool event) |
| `"phase":"tool"`   | 5 | ≥ 1 (one tool-call announcement per prompt) |
| `"phase":"output"` | 1 | ≥ 1 (the bash echo) |
| `"phase":"finish"` | 5 | ≥ 1 (each block closes) |
| `"stop_reason"`     | 5 | ≥ number of prompts (5) — every turn-end `ready` carries a stop reason |
| `"t":"ready"`       | 6 | 1 startup + 5 turn-ends |

Tool names announced: `write`, `read`, `edit`, `list`, `bash` (all five present — the wire
carries the full file/shell zoo). The bash `output` event is the literal
`{"t":"tool","phase":"output","idx":0,"s":"hello-world\n",…}`. The 5 turn-end `ready` events all
carry `"stop_reason":"eos"` (plus `generated` and `ctx_used` — the D12 fields); the startup
`ready` carries none, as specified.

**Confinement proof.** `seed.txt` was created **inside** `/tmp/swiftstar-p9-workspace/`
(content `hi from golden-tools` — the `write` ran, then the `edit` replaced `hello`→`hi`), and
no `seed.txt` leaked into `external/ds4/` — proving the file tools ran under the `--workspace`
grant rather than the bare-CLI cwd. (Without the driver fix below, `--workspace`/`--shell` were
silently dropped and `seed.txt` instead landed in `external/ds4/`; that shape was rejected.)

## Driver fix recorded for the fixture

The brief's Step 1 sketch used `process.arguments?.append(...)`. `Process.arguments` is a
Foundation **`copy`** property, so appending via optional chaining mutates a throwaway copy and
does not persist — `--workspace`/`--shell` were silently dropped and the engine ran in bare-CLI
mode (no confinement, shell on by default). `swiftstar-drive` now builds the argv on a local
`var args` and assigns once (`process.arguments = args`), which is what this fixture was
captured with. The Metal env vars are set via `engineEnv[…] = …; process.environment = engineEnv`
(an assign-back), so they always persisted.

## Recapture rule

This fixture is the sanctioned output of `swiftstar-drive` with the P7 consent knobs. **On every
submodule bump, it must be recaptured** against the freshly rebuilt binary (`just engine`, then
the `CAPTURE_WORKSPACE`/`CAPTURE_SHELL`/`CAPTURE_PROMPTS_FILE` `just capture` above), because a
rebase can apply cleanly and still be semantically wrong — and the tool-phase zoo plus the D12
turn-outcome fields are exactly what a recapture re-verifies. Re-verify the Step 4 greps
(tool phases, `stop_reason` ≥ prompt count, `seed.txt` inside the workspace) before installing.
The P9 recapture additionally confirms the `tool_request`-free, engine-internal shape
(`--host-tools` off); the `--host-tools`-on round trip is `FakeHostToolsIntegrationTests`, not
this live capture.
