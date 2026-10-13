---
description: Report on the newest ds4-engine session for this repo (flagged steps, time, context and speed), with no model digging
argument-hint: "[--session DIR] [--json] [a question about the session]"
allowed-tools: Bash(just last:*)
---

The user typed: `$ARGUMENTS`

Split that into flags and a question. Flags are `--session DIR` and `--json`;
everything else is a question about the session, not an argument. Run
`just last` with the flags only (none is fine) and show its output exactly as
printed, with no commentary before it.

If there was a question, answer it next, from the report. Otherwise wait for
the user's follow-up. Answer from the report first. Open the
session's files (`operator-events.jsonl`, `receipt.json`, the `run-*.json`
capture in the directory the report names) only for the steps or rows the
user asks about, and read just those parts. Don't reconstruct the telemetry
the report already computed. The conversation the model actually saw is
`conversation.json` in the same directory.

The report's rules: F1 a tool call failed, F2 the engine failed, F3 a prompt
got no answer, U1 the engine answered with a guard notice (already shown, a
repeated call, a call cycle), U2 a plain repeat of an earlier call with no
write to that path in between, R1 one pause's prefill took over 10 s (often
a full refill after a rewind or resume without saved state). Per-pause
rates are deltas between checkpoints, not session averages.
