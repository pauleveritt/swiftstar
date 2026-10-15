---
description: Report on the newest ds4-engine session for this repo (time, rates, prompts, syncs, proposals), with no model digging
argument-hint: "[SESSION-ID-OR-DIR] [--json] [--turn N] [a question about the session]"
allowed-tools: Bash(just last:*)
---

The user typed: `$ARGUMENTS`

Split that into arguments and a question. The arguments are a session id or
directory (first, if given), `--json` and `--turn N`; everything else is a
question about the session. Run `just last` with the arguments only (none is
fine) and show its output exactly as printed, with no commentary before it.

If there was a question, answer it next, from the report. Otherwise wait for
the user's follow-up. Answer from the report first. Open the
session's files (`operator-events.jsonl`, `receipt.json`, the `run-*.json`
capture in the directory the report names) only for the steps or rows the
user asks about, and read just those parts. Don't reconstruct the telemetry
the report already computed. The conversation the model actually saw is
`conversation.json` in the same directory.

The report is ds4-engine's `ds4-dogfood report` (AN.4). Its labels are the
engine's and sit next to their figures: "short batch, fixed cost" is a sync of
32 tokens or fewer, which costs one padded tile, so its low rate isn't a cold
start; "nothing new to prefill" is a sync with no new tokens. Rates per sync
are that sync's own; the `rates` line is the whole session. A slow figure
with no label is unexplained, not cold: say so rather than guessing a cause.
