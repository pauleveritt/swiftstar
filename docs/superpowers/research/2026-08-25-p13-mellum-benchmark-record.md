# P13 Mellum benchmark — live-model verification record

**Date:** 2026-08-25
**What ran:** `swiftstar-agenttest --variant mellum-2.1 --spec roadmap`, three
arms: relative-path (default), absolute-path (`AGENTTEST_PATH_STYLE=absolute`),
and absolute-path + nudge (`DS4_AGENT_TOOL_NUDGE=2 AGENTTEST_PATH_STYLE=absolute`).
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
| absolute + nudge=2 | ~736 chars | **0** | 0 | eos |

Every arm ended in `validationFailed` on an **empty candidate tree** (the
`sha256:e3b0c44…` digest is the empty tree): Mellum narrated a complete,
correct-in-content solution — including the exact `uv run … pytest` commands —
and stopped without ever emitting a tool call or writing a file. Absolute paths
produced only *more* narration (899 vs 348 tokens), not initiation; the nudge
arm re-narrated ("…Let me write these files:") and still emitted nothing.

## Why this contradicts B8 — and the nudge is not the missing piece either

B8's optimistic cell (absolute paths → 6 tool calls, 4/4 files) **did not
replicate**, and neither did its implied lever. The 2×2 (path × nudge) in the
current harness:

| | nudge=0 | nudge=2 |
|---|---|---|
| relative | 0 calls | (B8: 0 calls) |
| absolute | 0 calls | **0 calls** (this run) |

B8 held `DS4_AGENT_TOOL_NUDGE=2` and varied path (relative→0, absolute→6); the
current harness holds nudge=0 and varies path (0→0), and now nudge=2 + absolute
gives 0. So the nudge is neither sufficient nor, in this harness, the trigger.
The A1 finding — *protocol compliance is solved; agent competence is not* —
reproduces cleanly through the variant harness in every tested configuration.

## Sampling ruled out (not hostile)

GLM 5.2's next-step review flagged the undocumented sampler as an open
confound. Checking the source closed it: Mellum's engine default is
`ds4_engine_sampling_defaults` (ds4.c:63358) — **temp 0.6, top-k 20, top-p
0.95, min-p 0.0**, JetBrains' published tool-call setting, explicitly chosen
over the generic 1.0/1.0 because that "is a poor setting for a model expected
to emit well-formed JSON tool calls." The 0-call behavior is therefore **not**
a sampling artifact. The `Variant` now declares these values and the capture
records them.

## Verdict

Per D9's failure policy (no initiation ⇒ Mellum is not shipped as a preset and
P13-Mellum blocks), **the competence gate fails.** The variant plumbing is
complete and correct; the model does not clear the initiation floor under any
of path presentation × nudge, at the published tool-call sampler. The durable
lever is the out-of-phase harness work (the P9/P10 host-controlled action mode
— declared objectives, host-reported state, never-trust-claimed-test-results) —
not P13 scope.
