#!/usr/bin/env python3
"""Record one `ds4-dogfood tui --ndjson` session as a SwiftStar fixture.

Every stdout line is written to the output verbatim: the fixture is exactly
what `EngineWireParser` reads. The engine's own capture directory goes to a
throwaway temp dir. See fixtures/engine/provenance.md.

    record-engine-fixture.py <ds4-dogfood> <source-repo> <scenario> <out.ndjson> [seed]

Scenarios:
  tool-read  one prompt that should call `read`, then quit
  stop       a long prompt; `stop` after the first tool_result, then quit
  error      an unknown message kind at the first input, then quit
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROMPTS = {
    "tool-read": "Use the read tool on Package.swift, then answer in English: "
    "what targets does it declare?",
    "stop": "Read every file under Sources/SwiftStarKit/ one at a time, from "
    "the first to the last, then summarize each one in a paragraph.",
}


def main() -> int:
    exe, source, scenario, out = sys.argv[1:5]
    seed = sys.argv[5] if len(sys.argv) > 5 else "7"
    if scenario not in ("tool-read", "stop", "error"):
        sys.exit(f"unknown scenario: {scenario}")
    capture = Path(tempfile.mkdtemp(prefix="engine-fixture-")) / "session"
    command = [
        exe, "tui", "--ndjson",
        "--model-id", "laguna-xs-2.1", "--context-size", "20000",
        "--seed", seed, "--source", source, "--commit", "HEAD",
        "--capture-dir", str(capture),
    ]
    proc = subprocess.Popen(
        command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )

    def send(message: dict) -> None:
        proc.stdin.write(json.dumps(message) + "\n")
        proc.stdin.flush()

    inputs = 0
    stopped = False
    with open(out, "w") as sink:
        for raw in proc.stdout:
            sink.write(raw)
            line = json.loads(raw)
            kind = line.get("kind")
            event = (line.get("event") or {}).get("kind")
            if kind == "input":
                inputs += 1
                if inputs == 1 and scenario == "error":
                    send({"kind": "bogus"})
                elif inputs == 1:
                    send({"kind": "prompt", "text": PROMPTS[scenario]})
                else:
                    send({"kind": "quit"})
            elif kind == "error" and scenario == "error":
                send({"kind": "quit"})
            elif event == "tool_result" and scenario == "stop" and not stopped:
                stopped = True
                send({"kind": "stop"})
    code = proc.wait()
    print(f"{scenario}: exit {code}, capture {capture}", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
