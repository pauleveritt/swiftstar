# SwiftStar P29.9 design: model picker via engine options

**Date:** 2026-09-28  
**Status:** design, approved in chat by the owner (2026-09-28)  
**Phase:** P29 — Make the front-end honest (step P29.9, first cycle)

## Goal

Let the user choose which model and context size the engine runs, from
SwiftStar, by passing ds4-engine's own options to `ds4-dogfood tui`:
`--model-id <id>` and `--context-size <n>`. Today the only way to run Qwen
3.8 was a wrapper script set as the executable path.

## Decisions

1. **Two Settings fields, both optional.** "Model" (engine model id, text;
   empty = the engine's default: saved model, else Laguna XS) and "Context
   size" (integer; empty = the engine's largest measured size that fits).
   Stored with `@AppStorage` keys `engineModelID` and `engineContextSize`.
   The help text names two ids that exist today (`laguna-xs-2.1`,
   `qwen3.8-flash-next`) as examples; SwiftStar keeps no model registry.
2. **argv.** `EngineCommand.arguments(source:modelID:contextSize:)` appends
   `--model-id <id>` when the id is non-empty after trimming, and
   `--context-size <n>` when `n > 0`. Empty settings produce exactly the
   P28 argv.
3. **Show what actually loaded.** The engine's `session` event
   (`model_id`, `context_size`) is kept in `EngineTranscript` as
   `session: EngineSessionInfo?`; the toolbar shows the model id and context
   size of the running session.
4. **Apply on the next session.** Changing a setting does not kill a running
   session. While the running session's model or context differs from
   Settings, the toolbar offers "Restart to use <model>", which quits the
   session and starts a new one. (Refinement of the chat design, which had a
   confirmation on change; a dialog raised from the Settings window was
   judged worse.)
5. **Refusals are the engine's.** An unknown id, a model not on this Mac, or
   a context that doesn't fit ends in the existing exit-2 path: "refused to
   start: " + the engine's argparse line.

## Out of scope

A dropdown of models. It needs a machine-readable list from the engine
(`ds4-dogfood models --json`: id, name, on disk, fits, measured contexts),
which does not exist yet; recorded as a follow-up for ds4-engine.

## Testing

- Fast tier: argv for each combination (both empty, id only, context only,
  both, whitespace id, zero/negative context); `EngineTranscript` keeps
  `session` from the fixture's `session` event and clears it on `.closed`.
- Integration: the fake engine logs its argv (`FAKE_ENGINE_ARGV_LOG`); a
  test asserts `--model-id` and `--context-size` arrive.
- Live: SwiftStar with Model `qwen3.8-flash-next`, no wrapper; the toolbar
  shows `qwen3.8-flash-next` and 20,000.

## Success criteria

1. With both fields empty, argv is byte-identical to P28's.
2. With Model = `qwen3.8-flash-next`, the live engine's `session` event
   reports that model, and the toolbar shows it.
3. A bogus id shows "refused to start: …" with the engine's reason.
