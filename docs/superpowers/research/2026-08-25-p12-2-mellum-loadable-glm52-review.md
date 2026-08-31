# SwiftStar P12.2 — GLM 5.2 adversarial review

**Date:** 2026-08-25
**Reviewer:** `z-ai/glm-5.2` (OpenRouter), read-only, dispatched via `pi -p --no-session`.
**Reviewed:** `docs/superpowers/specs/2026-08-25-p12-2-mellum-loadable-design.md` and `docs/superpowers/plans/archive/2026-08-25-p12-2-mellum-loadable.md`, verified against `~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum` (tip `cde6438`).

## Verified facts (reviewer's verdicts, re-checked against source)

1. **Merge geometry** — VERIFIED. `merge-base(cde6438, 1f9a4c5)` = `8784fe6`; both reachable in `~/projects/ds4`. **Correction adopted:** the think-budget side is a *single* commit (`1f9a4c5`, parent `8784fe6`) touching four files (`ds4.c`, `ds4.h`, `ds4_agent.c`, `ds4_help.c`), so the conflict surface is confined to those four files.
2. **Bug location & fix** — PARTIALLY VERIFIED. Binder at `ds4.c:37323` only reads `ffn_gate_exps->type`; fix placement (after `weights_mellum_layer_has_required`, before `layer_gate_down_expert_bytes`) is correct. **The failure-class analysis was wrong** (see I3).
3. **Fix correctness** — VERIFIED. `if (ffn_down_exps->type != DS4_TENSOR_Q8_0) return false;` cleanly rejects every non-Q8_0 down; no genuine down type is wrongly rejected.
4. **Crafted-artifact viability** — VERIFIED. `model_open` reads only header/metadata/directory; `inspect_only` skips prefetch; `load_slice && start==1` skips token_embd and binds only layer 1; `config_validate_mellum_model` requires every `mellum.*` scalar + 28-entry sliding-window pattern. All metadata keys/values match source.
5. **Tensor dims** — VERIFIED. `q_dim=4096`, `kv_dim=512`, all layer-1 names/dims match `weights_bind_mellum_layer`/`weights_validate_mellum_layout`.
6. **Sparse-file bounds** — VERIFIED. `parse_tensors` enforces `abs_offset <= size && bytes <= size - abs_offset`; largest tensor (Q8_0 gate/up/down) is ~134 MiB; the 2× cover (264,241,152 bytes = 252 MiB) is ample.
7. **Test hook** — VERIFIED. `g_ds4_shape` is file-scope static settable in-TU; the Q8_0 positive control yields `gate_expert_bytes == up_expert_bytes`; `weights_mellum_layer_has_required` only needs 12 non-NULL pointers.
8. **Link lines** — VERIFIED. Both new link lines mirror existing targets; no `rax.o`/`ds4_kvstore.o`/`ds4_metal.o` needed for `-DDS4_NO_GPU` on Darwin.
9. **Submodule bump** — VERIFIED. `.gitmodules` already points `external/ds4` at `pauleveritt/ds4`; the fetch/checkout/commit flow is sound.

## Issues

### Critical
None.

### Important (all fixed before implementation)

- **I1 — Q5_0 type id was wrong.** The generator and test hook used `Q5_0 = 9`; per `gguf_types[]`, type 9 is **q8_1** and real **Q5_0 is type 6**. Fixed: generator `Q5_0 = 6`, hook `down->type = 6`.
- **I2 — "red" prediction was wrong.** Pre-fix, a non-Q8_0 down that isn't a routed-expert-block type (`Q5_0`/`Q4_0`/`q8_1`) `ds4_die`s in `routed_expert_block_bytes` (default case), not "unexpectedly accepted". Fixed: the plan's red-step text and the hook order (MXFP4, the only pre-fix *silently accepted* type, is tested first).
- **I3 — Spec failure-class analysis was wrong.** `Q4_0`/`Q5_0` are not silently accepted — they die in `routed_expert_block_bytes`. Only **MXFP4** is silently accepted. Fixed in the spec's "Gardenable facts" and D2/D3 prose.

### Minor
- M1/M2 — "~140 MiB" / "264 MiB" byte-vs-MiB looseness and the bad-fixture-size comment: corrected in the generator comment.
- M3 — `general.alignment` is written but not strictly required (harmless); no action.
- M4 — Fix+tests landing as commits on top of the merge (not inside it) is appropriate; no change.

## Assessment

**Ready to implement: With fixes** (all Important issues now folded into the spec/plan). The one-line fix, its placement, the admission path, the metadata/dims contract, the link lines, and the submodule flow are all correct against source. The Q5_0 type-id error and the failure-class prose have been corrected so the test exercises the type official mixed artifacts actually use, and the plan's red-step expectation now matches real pre-fix behavior.
