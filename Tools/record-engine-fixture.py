#!/usr/bin/env python3
"""Record `ds4-dogfood tui --ndjson` sessions as SwiftStar fixtures.

Every stdout line is written to the output verbatim: the fixture is exactly
what `EngineWireParser` reads. The engine's state and config go to a
throwaway temp dir (XDG_STATE_HOME, XDG_CONFIG_HOME), so a recording never
touches the user's own sessions. See fixtures/engine/provenance.md.

    record-engine-fixture.py <ds4-dogfood> <source-repo> <scenario> <out.ndjson> [seed] [model]

Scenarios:
  tool-read        one prompt that should call `read`, then quit
  stop             a long prompt; `stop` after the first tool_result, then quit
  error            an unknown message kind at the first input, then quit
  relaunch-rewind  two prompts, then `/rewind 1`; quits at the refusal, then
                   runs its `relaunch` argv and records that process to
                   `resumed.ndjson` beside <out.ndjson>
  tool-rejected    asks for the same read three times, to trip the loop
                   guard; exits 3 if no call was rejected (try another seed)
  bash-run         under --allow-bash (SU.18), a `cat` the engine maps onto
                   `read` and a piped command it runs as bash
  resumed-answered three sessions in one scratch state (EN.2): a prompt at
                   context 20000; a prompt at 16384, recorded to
                   `prefix-changed.ndjson` beside <out.ndjson> (its prefix
                   miss names `context`); then that session resumed with one
                   more prompt, recorded to <out.ndjson> (its
                   `conversation_state`). The resumed session's directory is
                   printed for `fixtures/sessions/`.
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

PROMPTS = {
    "tool-read": "Use the read tool on Package.swift, then answer in English: "
    "what targets does it declare?",
    "stop": "Read every file under Sources/SwiftStarKit/ one at a time, from "
    "the first to the last, then summarize each one in a paragraph.",
    # SU.18, D5: under --allow-bash, one `run` the engine maps onto `read`
    # and one it can only run as bash (a pipe).
    "bash-run": "Use the run tool twice: first run `cat Package.swift`, then run "
    "`ls Sources | wc -l`. Then answer in one sentence: how many entries does Sources have?",
    # The 27B won't call a tool that doesn't exist (seeds 1-6, 2026-10-13),
    # so this provokes the loop guard's `repeated-call` instead.
    "tool-rejected": "Use the read tool on Package.swift three times in a "
    "row with exactly the same arguments, then answer in one sentence.",
}
REWIND_PROMPTS = [
    "Answer in one short sentence, without tools: what is 2 + 2?",
    "Answer in one short sentence, without tools: what is 3 + 3?",
]
SCENARIOS = ("tool-read", "stop", "error", "relaunch-rewind", "tool-rejected", "resumed-answered", "bash-run")


def one_prompt(text, seen):
    """An `on_line` that sends `text` at the first `input` and quits at the
    next, noting the session's directory from a checkpoint's capture path."""
    state = {"inputs": 0}

    def on_line(line, send):
        event = line.get("event") or {}
        path = (event.get("snapshot") or {}).get("capture_path")
        if event.get("kind") == "checkpoint" and path:
            seen["directory"] = str(Path(path).parent)
        if line.get("kind") == "input":
            state["inputs"] += 1
            send({"kind": "prompt", "text": text} if state["inputs"] == 1 else {"kind": "quit"})

    return on_line


def record_resumed_answered(exe, source, out, env, seed, model):
    """The `resumed-answered` scenario (EN.2): returns its exit code."""
    base = ["tui", "--ndjson", "--model-id", model, "--seed", seed, "--source", source, "--commit", "HEAD"]
    scratch_out = str(Path(out).with_name("first-run.scratch.ndjson"))
    changed_out = str(Path(out).with_name("prefix-changed.ndjson"))
    first, second, third = {}, {}, {}
    code = run(exe, [*base, "--context-size", "20000"], env, scratch_out, one_prompt(REWIND_PROMPTS[0], first))
    keep(scratch_out, False)
    if code:
        return code
    code = run(exe, [*base, "--context-size", "16384"], env, changed_out, one_prompt(REWIND_PROMPTS[1], second))
    if code or "directory" not in second:
        keep(changed_out, False)
        return code or 3
    resume = ["tui", "--ndjson", "--resume", Path(second["directory"]).name, "--source", source]
    try:
        code = run(exe, resume, env, out, one_prompt("Answer in one short sentence, without tools: what is 4 + 4?", third))
    except BaseException:
        keep(changed_out, False)
        raise
    ok = code == 0
    keep(changed_out, ok)
    keep(out, ok)
    print(f"resumed-answered: exit {code}, resumed session {third.get('directory')}", file=sys.stderr)
    return code


def run(exe, argv, env, out, on_line):
    """Run `exe ARGV`, write its stdout to `out + ".tmp"`, call
    `on_line(line, send)` for each parsed line; return the exit code. The
    caller keeps the recording (`keep`) or drops it, so a failed attempt
    never overwrites a committed fixture."""
    # The `with` closes the pipes and reaps the process, however it ends (SU.17).
    with subprocess.Popen(
        [exe, *argv], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, bufsize=1, env=env,
    ) as proc:

        def send(message: dict) -> None:
            proc.stdin.write(json.dumps(message) + "\n")
            proc.stdin.flush()

        try:
            with open(out + ".tmp", "w") as sink:
                for raw in proc.stdout:
                    sink.write(raw)
                    on_line(json.loads(raw), send)
        except BaseException:
            # A failed recording leaves nothing behind (SU.6g, D5).
            proc.kill()
            Path(out + ".tmp").unlink(missing_ok=True)
            raise
        return proc.wait()


def run_resumed(exe, argv, env, out, resumed):
    """Record the relaunch's resumed half, quitting at its first `input`.
    If it raises, the first half's recording goes too (SU.17): the two are
    kept together or not at all (`settle_pair`)."""

    def quit_at_input(line, send):
        if line.get("kind") == "input":
            send({"kind": "quit"})

    try:
        return run(exe, argv, env, resumed, quit_at_input)
    except BaseException:
        keep(out, False)
        raise


def main() -> int:
    exe, source, scenario, out = sys.argv[1:5]
    seed = sys.argv[5] if len(sys.argv) > 5 else "7"
    model = sys.argv[6] if len(sys.argv) > 6 else "qwen3.8-27b"
    if scenario not in SCENARIOS:
        sys.exit(f"unknown scenario: {scenario}")
    scratch = Path(tempfile.mkdtemp(prefix="engine-fixture-"))
    env = dict(os.environ, XDG_STATE_HOME=str(scratch / "state"),
               XDG_CONFIG_HOME=str(scratch / "config"))
    if scenario == "resumed-answered":
        return record_resumed_answered(exe, source, out, env, seed, model)
    argv = [
        "tui", "--ndjson", "--model-id", model, "--context-size", "20000",
        "--seed", seed, "--source", source, "--commit", "HEAD",
    ] + (["--allow-bash"] if scenario == "bash-run" else [])
    state = {"inputs": 0, "stopped": False, "relaunch": None, "rejected": False}

    def on_line(line, send):
        kind = line.get("kind")
        event = line.get("event") or {}
        if kind == "input":
            state["inputs"] += 1
            n = state["inputs"]
            if scenario == "error" and n == 1:
                send({"kind": "bogus"})
            elif scenario == "relaunch-rewind" and n <= 2:
                send({"kind": "prompt", "text": REWIND_PROMPTS[n - 1]})
            elif scenario == "relaunch-rewind" and n == 3:
                send({"kind": "prompt", "text": "/rewind 1"})
            elif scenario in PROMPTS and n == 1:
                send({"kind": "prompt", "text": PROMPTS[scenario]})
            else:
                send({"kind": "quit"})
        elif kind == "error" and scenario == "error":
            send({"kind": "quit"})
        elif event.get("kind") == "tool_result" and scenario == "stop" and not state["stopped"]:
            state["stopped"] = True
            send({"kind": "stop"})
        elif event.get("kind") == "rewind_refused" and event.get("relaunch"):
            state["relaunch"] = event["relaunch"]
        elif event.get("kind") == "tool_rejected":
            state["rejected"] = True

    code = run(exe, argv, env, out, on_line)
    print(f"{scenario}: exit {code}, scratch {scratch}", file=sys.stderr)
    if scenario == "tool-rejected" and not state["rejected"]:
        keep(out, False)
        print("tool-rejected: no tool_rejected event; try another seed", file=sys.stderr)
        return 3
    if scenario == "relaunch-rewind":
        if not state["relaunch"]:
            keep(out, False)
            print("relaunch-rewind: no rewind_refused with relaunch", file=sys.stderr)
            return 3
        resumed = str(Path(out).with_name("resumed.ndjson"))
        resumed_code = run_resumed(exe, state["relaunch"], env, out, resumed)
        print(f"resumed: exit {resumed_code}, argv {state['relaunch']}", file=sys.stderr)
        settle_pair(out, resumed, code, resumed_code)
        return code or resumed_code
    keep(out, code == 0)
    return code


def settle_pair(out, resumed, code, resumed_code):
    """Keep a relaunch-rewind recording and its resumed half together or not
    at all (SU.6g, D5): one without the other pairs a new recording with an
    old one."""
    ok = code == 0 and resumed_code == 0
    keep(out, ok)
    keep(resumed, ok)


def keep(out, ok):
    """Move a finished recording into place, or drop it."""
    tmp = Path(out + ".tmp")
    if ok:
        tmp.replace(out)
    else:
        tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
