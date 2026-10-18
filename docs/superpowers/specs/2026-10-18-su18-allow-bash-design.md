# SwiftStar SU.18 design: run with `--allow-bash`, and show the fallback

Date: 2026-10-18. Status: **accepted by the owner, 2026-10-18; revised
below (on by default).**

## Goal

Let the owner turn on ds4-engine's `--allow-bash`. A transcript card then
shows when a `run` call fell back to bash in the sandbox, with what is
known of it: its exit, its time and its output.

Showing a `run` the engine turned into a plain `read`, `ls` or `grep`, and
the bash command's own text, needs the engine to put them on the wire.
They go to the engine as a request (D4).

## What the engine does (ds4-engine `a84b79bd`, read only, nothing run)

- **The flag.** `tui --allow-bash` is the RUN.2 experiment, "not a shipped
  default" (`specs/2026-10-01-run2-bash-fallback-design.md:3`, `:41`). Its
  default is `config.toml`'s `run_bash`, and there's no `--no-allow-bash`
  (`tui_cli.py:622-631`, `:840-847`). Under it, a model call named `shell`
  or `bash` is read as `run` (`driver.rs:1091-1093`).
- **A mapped `run`.** A simple `cat`, `ls` or `grep` becomes that tool's own
  call, and goes on the wire as a plain `read`, `ls` or `grep` (`driver.rs:3334-3339`).
  Its `converted_from: "bash command"` marker is only in the capture's
  `turns[].tool.args` (`:4804-4805`).
- **A bash run.** Anything else is `bash -c` under `sandbox-exec`, in the
  candidate worktree (`run_tool.py:53-65`, `:159-167`):
  - **Limits:** 120 s, after which the process group is killed (`:32`,
    `:139-144`).
  - **Network:** denied.
  - **Writes:** only in the worktree and the temp directories.
  - **What reaches the wire:** `tool_start`, `tool_end` and `tool_result`
    with `op: "run"` and `path: ""`.
    - `preview` is the merged stdout and stderr, headed `[exit N in X.X s]`,
      or `[stopped after 120 s, the time limit]` (`run_tool.py:119-124`).
    - `result_kind` is `"ok"` even when the exit isn't 0 (`:176`).
  - **The command text** is not on the wire, only in the capture's args
    (`driver.rs:4757-4766`).
  - **Its edits** land in the worktree and in `candidate.diff`
    (`candidate.py:109-119`).
- **Off.** With bash off and no `--allow-run`, a `run` is `tool_rejected`,
  `unknown-tool`, as SwiftStar shows today.
- **Startup:** nothing says bash is on. Not `session`, not the receipt
  (`tui_cli.py:1101-1122`). The flag survives `/resume`, `/model` and
  `/rewind`: their `relaunch` argv carries it (`tui_cli.py:443-446`).

## Decisions

- **D1. A Settings toggle, off by default.** It reads "Let the model run
  shell commands (experimental)".
  - **Saving:** under `DefaultsKey.allowBash`.
  - **Spawning:** `EngineCommand.arguments(…, allowBash:)` and
    `resumeArguments(…, allowBash:)` append `--allow-bash`. SwiftStar's own
    resumes (the sidebar, the Recent menus, Analyze's fork and Done) carry
    it the way the engine's `relaunch` does.
  - **When it applies:** at the next start, as a model choice does. Its
    help says so, and says that `config.toml`'s `run_bash = true` turns it
    on whatever the toggle says.
- **D2. A bash run's card says it fell back.**
  - **The card:** a `run` card with an empty path has the header "bash",
    a terminal icon, and the line "ran as bash in the sandbox".
  - **The metadata** comes from the output's first line: "exit 1 · 2.3s", or
    "stopped at the 120 s limit".
  - **Exit not 0:** the card's facts line turns red, as a failed call's does,
    since the engine's `result_kind` says ok.
  - **No command:** the header can't show what ran until D4.
- **D3. The Session card says bash is on** for a session SwiftStar started
  with the flag: "Shell: bash fallback on". It comes from the argv
  SwiftStar launched or relaunched with, since the engine reports nothing.
- **D4. An engine request, filed on the owner's go.** On the tool events of
  a call that came from `run`:
  - `via: "run"`, with `command` holding the model's text
  - on a bash run, `command` as well, and an `exit` field next to the
    header
  - in `session`, the tool policy: `run_bash` and `run_allow`
  - the report's `turns[].calls` keeping `converted_from`

  It also names the inferred `converted_from` leak after a refused mapped
  call (`driver.rs:3338`, `:4804`). Once the engine sends these, a mapped
  card reads "read Package.swift · via run (`cat Package.swift`)", and a
  bash card shows its command.
- **D5. A recording, on the owner's GPU go.** `just capture bash-run`, with
  `--allow-bash`, asks for one mapped and one bash command. Until it lands,
  the tests use the engine's own test payloads (`tests/test_run_tool.py` and
  `driver.rs`'s tests), named as such in `provenance.md`.

## Testing

- **Fast tier:**
  - `arguments` and `resumeArguments` with and without `allowBash`
  - the bash card's header, icon, line and metadata for exit 0, exit 1 and
    the time limit, and red only when it failed
  - the Session card's shell row on and off

  Each is shown to fail with its behavior broken.
- **Integration:**
  - the fake engine's spawn log has `--allow-bash` when the setting is on,
    on the start and on a sidebar resume
  - a bash `tool_result` fixture line makes the card
- **Previews:** rendered:
  - bash cards for exit 0, exit 1 and the limit
  - the Settings toggle
  - the Session card's row

## Done when

- D1–D3 are built, with both tiers green and the previews looked at.
- D4 is filed or deferred, as the owner says.
- D5 waits for the owner's GPU go.
- ROADMAP and CHANGELOG are updated.

## Risks

- **RUN.2 is an experiment.** Reads outside the worktree aren't denied in
  its sandbox (`run_tool.py:13-14`), so the toggle's help says the command
  runs on this Mac with network off.
- **Turning the flag off may not work.** With `run_bash = true` in
  `config.toml`, the toggle can't turn it off, so the help says that too.
- **A mapped call can't be shown until D4.** Until then, a `cat` the model
  ran looks like a `read` it made.

## Revision, 2026-10-18: on by default

The owner's call, after the build: D1's toggle is **on** unless turned off.
`DefaultsKey.allowBashDefault` is `true`, so a setting that was never saved
means on. The toggle still turns it off. The Risks still hold: the engine
calls RUN.2 an experiment, and its sandbox doesn't deny reads outside the
worktree.

