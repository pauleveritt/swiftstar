# P13 Mellum — GLM 5.2 status review + next steps

**Date:** 2026-08-25
**Reviewer:** `z-ai/glm-5.2` (OpenRouter), read-only, dispatched via `pi -p --no-session`.
**Reviewed:** P13-Mellum implementation + live benchmark result (concise status review).

## Review

- **"Block, don't ship" is sound.** D9 is binary; both benchmark arms hit 0 tool
  events / 0 files / empty-candidate-tree. The run cleanly separates proven
  *machinery* from unproven *model* competence.
- **B8 non-replication is the sharper result.** B8 held `DS4_AGENT_TOOL_NUDGE=2`
  and varied path (relative→0, absolute→6 calls); the current run held nudge=0
  and varied path (0→0). Together: **nudge is necessary; given nudge, path is
  the trigger.** This overturns "path shape alone flips it."
- **Uncontrolled confound (owned):** Mellum ran on an *undocumented engine
  family-default sampler* (D6 deliberately unwired it). Hostile temp/top-k/top-p
  would produce exactly the 0-call/narration signature and was never swept. The
  run proves "default-sampling + no-nudge does not initiate," not "Mellum
  cannot initiate."
- **No flaw in the Variant machinery or measurement.** Gate ordering,
  missing-tensor-as-mismatch, gate-synthesized `.unreadableFile`,
  memory-as-function-of-ctx, single-resolver consolidation all match the spec;
  456 tests green. n=1 per arm is fine — 0/0 is a hard floor.

## Next steps (ranked)

1. Re-run with a forcing function (nudge-equivalent / "retry requires a
   registered tool call" gate) — B8 shows this alone flips 0→6.
2. Wire + sweep Mellum sampler defaults to rule out sampling as the 0-call
   cause before the competence verdict hardens.
3. Replicate B8's clean ablation in the current harness (absolute paths +
   `DS4_AGENT_TOOL_NUDGE=2`) to localize nudge-vs-path.
4. Land the Variant plumbing as infrastructure independent of the Mellum preset
   (done — plumbing is committed and orthogonal to the preset).
5. P9/P10 host-controlled action mode as the durable fix for Mellum agency.
