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
    # The 27B won't call a tool that doesn't exist (seeds 1-6, 2026-10-13),
    # so this provokes the loop guard's `repeated-call` instead.
    "tool-rejected": "Use the read tool on Package.swift three times in a "
    "row with exactly the same arguments, then answer in one sentence.",
}
REWIND_PROMPTS = [
    "Answer in one short sentence, without tools: what is 2 + 2?",
    "Answer in one short sentence, without tools: what is 3 + 3?",
]
SCENARIOS = ("tool-read", "stop", "error", "relaunch-rewind", "tool-rejected")


def run(exe, argv, env, out, on_line):
    """Run `exe ARGV`, write its stdout to `out + ".tmp"`, call
    `on_line(line, send)` for each parsed line; return the exit code. The
    caller keeps the recording (`keep`) or drops it, so a failed attempt
    never overwrites a committed fixture."""
    proc = subprocess.Popen(
        [exe, *argv], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, bufsize=1, env=env,
    )

    def send(message: dict) -> None:
        proc.stdin.write(json.dumps(message) + "\n")
        proc.stdin.flush()

    with open(out + ".tmp", "w") as sink:
        for raw in proc.stdout:
            sink.write(raw)
            on_line(json.loads(raw), send)
    return proc.wait()


def main() -> int:
    exe, source, scenario, out = sys.argv[1:5]
    seed = sys.argv[5] if len(sys.argv) > 5 else "7"
    model = sys.argv[6] if len(sys.argv) > 6 else "qwen3.8-27b"
    if scenario not in SCENARIOS:
        sys.exit(f"unknown scenario: {scenario}")
    scratch = Path(tempfile.mkdtemp(prefix="engine-fixture-"))
    env = dict(os.environ, XDG_STATE_HOME=str(scratch / "state"),
               XDG_CONFIG_HOME=str(scratch / "config"))
    argv = [
        "tui", "--ndjson", "--model-id", model, "--context-size", "20000",
        "--seed", seed, "--source", source, "--commit", "HEAD",
    ]
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

        def quit_at_input(line, send):
            if line.get("kind") == "input":
                send({"kind": "quit"})

        resumed_code = run(exe, state["relaunch"], env, resumed, quit_at_input)
        print(f"resumed: exit {resumed_code}, argv {state['relaunch']}", file=sys.stderr)
        keep(resumed, resumed_code == 0)
        code = code or resumed_code
    keep(out, code == 0)
    return code


def keep(out, ok):
    """Move a finished recording into place, or drop it."""
    tmp = Path(out + ".tmp")
    if ok:
        tmp.replace(out)
    else:
        tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
