# SwiftStar P13 — GLM 5.2 adversarial review

**Date:** 2026-08-25
**Reviewer:** `z-ai/glm-5.2` (OpenRouter), read-only, dispatched via `pi -p --no-session`.
**Reviewed:** `docs/superpowers/specs/2026-08-25-p13-mellum-variant-design.md`.

## Assessment

**Ready with fixes.** All Critical/Important issues folded into the spec before
implementation. The architecture (pure verifier + single gate + declared budget)
is sound; the review caught three bypasses that undermined the spec's central
claim ("verified before anything expensive happens") plus several sharp seams.

## Folded findings

**Critical**
- **C1** — gate was bypassable via `AgentController` and the fixture arm; "single
  admission entry point" was not single. → Added shared `VariantResolver` used by
  both controllers; the harness gates once at the top of `main.swift` before any
  `AgentSettings`/`PoolOrchestrator` construction, covering all three spawn sites.
- **C2** — the custom escape-hatch path re-opened the silent-wrong failure. →
  Custom/raw paths are now **declared unverified** (surfaced as such, never
  silently passed as verified), per D7.
- **C3** — the memory budget was keyed to 40k while `contextSize` is
  user-configurable. → `MemoryBudget.totalBytes(at:)` is now a function of
  context size (constant weights+scratch, linear KV anchored at 16k/32k/40k);
  ctx outside [16k, 40k] refused as unsupported.

**Important**
- **I1** — declared-vs-persisted plan precedence undefined. → Declared budget is
  the floor; `max(declared, persisted)` when a plan exists for the same
  variant+ctx.
- **I2** — harness `availableBytes` source unspecified. → Harness uses
  `MemorySnapshot.availableBytes()` and records it in `run-config.json`.
- **I3** — verifier purity vs `.unreadableFile` muddled. → `.unreadableFile` is
  gate-synthesized, never verifier-synthesized.
- **I4** — missing-tensor skip = silent pass. → Verifier iterates N explicitly;
  a missing layer is `.downQuant(... actual: .missing)`.
- **I5** — live gate had no failure policy. → D9: no initiation ⇒ Mellum is not
  shipped as a preset and P13-Mellum blocks.
- **I6** — shipping artifact's GGUF version assumed. → Verified against the real
  file (magic `GGUF`, version 3, 339 tensors); reader refuses wrong versions by
  name.
- **I7** — unwired undocumented sampler made run-config not self-describing. →
  `run-config.json` records `samplerSource: "engine-family-default (undocumented)"`.

**Minor (adopted in implementation)**
- M1 (variant/custom precedence defined), M2 (all new types `Sendable`; reader a
  `static func` owning its `FileHandle`; gate nonisolated), M3 (variant refusal is
  a pre-spawn direct assignment, consistent with `.infeasible`), M4 (shared
  resolver), M5 (reader seek-reads directory byte ranges, no fixed prefix), M6
  (performance recorded-not-gated; only initiation is gated).
