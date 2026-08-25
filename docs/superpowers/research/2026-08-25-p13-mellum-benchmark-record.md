# P13 Mellum benchmark — live-model verification record

**Date:** 2026-08-25
**What ran:** `swiftstar-agenttest --variant mellum-2.1 --spec roadmap`, two arms:
relative-path (default) and `AGENTTEST_PATH_STYLE=absolute`.
**Model:** Mellum 2.1, the 9.33 GiB shipping artifact
(`~/models/mellum-thinking-TARGET.gguf`).

## The variant machinery works end to end

- **Gate admitted the real artifact.** `VariantGate.admit` parsed the actual
  9.33 GiB GGUF (magic `GGUF` v3, 339 tensors) and verified architecture
  `mellum`, rope `yarn`@`500000.0`, and 28 Q8_0 down tensors — ADMIT, no
  crafted fixture.
- **Model loaded on the engine built from the pinned submodule** `f56d0ca`
  (the Mellum-loadable merge; the previously-built binaries predated it and
  were rebuilt first). Engine reported `resident model 9.33 GiB`, `9.99 GiB
  planned` at ctx=32768 — consistent with the declared `MemoryBudget`
  (9.33 weights + ~0.4 scratch + 0.48 KV ≈ 10.2 GiB).
- **`run-config.json` is self-describing** (I2/I7): `variant: mellum-2.1`,
  `samplerSource: engine-family-default (undocumented)`, `availableBytesGiB:
  84.3`, model path, think mode, tool budget.

## The competence floor (D9) was not met

| arm | generated | tool events | files written | stop |
|-----|-----------|-------------|---------------|------|
| relative (default) | 348 | **0** | 0 | eos |
| absolute | 899 | **0** | 0 | eos |

Both arms ended in `validationFailed` on an **empty candidate tree** (the
`sha256:e3b0c44…` digest is the empty tree): Mellum narrated a complete,
correct-in-content solution — including the exact `uv run … pytest` commands —
and stopped without ever emitting a tool call or writing a file. The
absolute-path arm only produced *more* narration (899 vs 348 tokens), not
initiation.

## Why this contradicts B8

B8's optimistic cell (absolute paths → 6 tool calls, 4/4 files) **did not
replicate** in the current harness. Two material differences, both noted in B8's
own caveats:

1. B8 ran with `DS4_AGENT_TOOL_NUDGE=2`; the pool harness has no nudge (A1
   recorded the nudge failing in the pool path, and P12 dropped it).
2. B8's prompt was the pre-P12.1 shape; the current `PhasePacketBuilder` packet
   is the engineered path-presentation form.

Either way, the A1 core finding — *protocol compliance is solved; agent
competence is not* — now reproduces cleanly through the variant harness, in
both path arms. The 0-call failure is not, in the current harness, a
path-presentation artifact.

## Verdict

Per D9's failure policy (no initiation ⇒ Mellum is not shipped as a preset and
P13-Mellum blocks), **the competence gate fails.** The variant plumbing is
complete and correct; the model does not clear the initiation floor. Further
progress is the out-of-phase harness work (the P9/P10 host-controlled action
mode, harvesting, or a different prompt strategy) — not P13 scope.
