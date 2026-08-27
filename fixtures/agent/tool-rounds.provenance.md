# `tool-rounds.ndjson` provenance

One **real** agent turn with host-tool round trips, sliced verbatim out of a
live app session — the shape the `golden.ndjson` chat capture does not have, and
the reason a decode average can be wrong by 8x without any test noticing.

- Source: `captures/live/20260826-214304/wire.ndjson`, the second turn (the
  turn's own `hello` is kept so the wire parses from a handshake).
- Model: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`, ctx 51,200, Metal.
- Captured: 2026-08-26 21:43 by the SwiftStar app (`--host-tools`, pooled wire).
- Shape: 148 `status` events, 72 `tool` events, 8 generation segments split by
  re-prefill, ending on a `ready` with `generated=298`.

What it pins (`TurnSummaryTests.toolRoundTurnTracksEngineRate`): the turn
generated **714** tokens across its 8 segments at **~56.9 tok/s**, while the
terminal `ready` alone reports 298 (the engine resets `generated` at every
prefill) and a wall-clock `Δgenerated/Δts` average over the same turn reads
**7.3 tok/s** — the wall clock contains prefill and tool-blocked time, which is
not decode time.

Slice, do not regenerate: the numbers above are the assertions.
