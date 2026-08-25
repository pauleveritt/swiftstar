# SwiftStar P12.2 design: Make Mellum loadable

**Date:** 2026-08-25
**Status:** accepted (brainstormed; decisions D1–D5 approved in-session; reviewed by GLM 5.2 — [`2026-08-25-p12-2-mellum-loadable-glm52-review.md`](../research/2026-08-25-p12-2-mellum-loadable-glm52-review.md); findings folded in).
**Phase:** P12 — Reliable agency, step P12.2.

This spec is the authority on *how* P12.2 is done. It covers the ds4 C-engine
side (merge + admission-contract hardening + tests) and the SwiftStar submodule
pin bump. The prior P12.2 fact-finding pass is treated as verified input, not
hypothesis.

## Problem

SwiftStar's submodule pins ds4 at `1f9a4c5` (`laguna-think-budget`). The Mellum
loader work that would let the app load a Mellum 2.1 artifact lives on the
unpushed branch `swiftstar-integration-mellum` (tip `cde6438`), which has not
been reconciled with the `--think-budget` lineage. Until they merge, the app
cannot load Mellum from the pinned submodule.

The reconciliation must also harden a real admission-contract bug in the Mellum
decode path. `ds4_engine_bind_mellum_decode_contract` (`ds4.c:37335`) infers the
routed-expert layout from `ffn_gate_exps`'s type alone and never inspects
`ffn_down_exps`. Today the bug is *masked*, not active:
`weights_validate_mellum_layout` (`ds4.c:5512-5524`, commit `180fb6a2`) already
`exit(1)`s on a non-Q8_0 down tensor, and `weights_bind()` runs that validator
before the vulnerable binder in the single engine-construction path. That is
fragile protection-by-ordering: any future caller that reaches the binder
without first passing the validator reopens the bug silently.

## Gardenable facts (verified against the source)

- **Merge geometry.** The Mellum branch tip `cde6438` and the pin `1f9a4c5` both
  descend from `8784fe6` (their exact merge-base). `~/projects/ds4` has both
  lineages fetched; the submodule checkout at `external/ds4` has only the pin.
  The similarly-named `swiftstar-integration` branches (local `0b3f0c7`, remote
  `4bd9a3d`) are 12 commits behind the same lineage; `mellum-repair-pipeline`
  (`9e21c05`) branches directly from `cde6438`. So the merge is a clean two-way
  merge from `8784fe6`, not a rebase.

- **Remotes.** `origin` = `antirez/ds4` (not writable by us); `pauleveritt` =
  `pauleveritt/ds4` (the push target).

- **The bug's three failure classes.** With `down = ffn_down_exps->type`, the
  current binder (which never reads `down`):
  - `Q4_0`/`Q5_0` (type 2/9, the types official mixed artifacts use for down):
    32-block, dim 896 block-aligned → `routed_expert_row_bytes` returns a byte
    count, `gate_expert_bytes == up_expert_bytes` still holds, and the binder
    **returns true** — a silently-wrong decode descriptor for a kernel that only
    executes Q8_0 down.
  - `MXFP4` (type 39): also a routed-expert type, 32-block, aligned → **returns
    true** — same silent bug.
  - K-quants (`Q4_K`=12 etc.): 256-block, 896 % 256 = 128 → `ds4_die("routed
    expert row is not quant block aligned")` — a hard exit, not a clean reject.

- **The fix must precede the byte math.** The down-type check must run before
  `layer_gate_down_expert_bytes` so that even K-quant downs become a clean
  `return false` rather than a die inside `routed_expert_row_bytes`.

- **The loader never reads tensor payload during admission.** `model_open` mmaps
  and parses header + metadata + tensor directory only; `tensor_expect_layout`
  checks `type`/`ndim`/`dim[]` only. Tensor bytes are never touched on the
  `model_open → config_validate_model → weights_bind → weights_validate_layout →
  ds4_engine_bind_mellum_decode_contract` path when `inspect_only` is set
  (prefetch is skipped). So a crafted GGUF needs correct *metadata and tensor
  directory* but not real payload bytes.

- **A single-layer fixture is enough.** `weights_bind` with
  `load_slice && load_layer_start == 1` sets `require_token_embd = false` and
  binds/validates only layer 1. `config_validate_mellum_model` still requires
  the full 28-entry `mellum.attention.sliding_window_pattern` and every
  `mellum.*` scalar, but only layer 1's twelve tensors must exist.

- **Crafted artifacts already exist** (for the optional heavy gate, not the
  committed test): `~/projects/ds4/gguf/mellum-quant-research/` holds
  `mellum-Q8_0.gguf` (all-Q8_0, valid), `mellum-down-Q5_0.gguf` and
  `mellum-down-MXFP4.gguf` (down-only quant variants, invalid), built via
  `llama-quantize` from `mellum-BF16.gguf`. They are gitignored and 10–12 GiB.

## Decisions

- **D1 — Merge in the ds4 repo, fresh branch, real merge commit.** Create a
  fresh worktree off `~/projects/ds4`, branch `swiftstar-integration-mellum-think-budget`
  rooted at `cde6438`, then `git merge 1f9a4c5`. Resolve any conflicts, build
  (`make`, `make test`), and push the branch to `pauleveritt/ds4`. No rebase, no
  force-push — the reconciliation must stay a visible merge commit, because a
  bad C-engine reconciliation risks silent memory corruption rather than a wrong
  test result. The fix and tests land as subsequent commits on the same branch.

- **D2 — The fix is a down-type check placed before the byte math.** In
  `ds4_engine_bind_mellum_decode_contract`, immediately after
  `weights_mellum_layer_has_required(src)` returns true, add:
  `if (src->ffn_down_exps->type != DS4_TENSOR_Q8_0) return false;`.
  This is the entire fix. It converts all three failure classes (Q4_0/Q5_0,
  MXFP4, K-quants) into a clean rejection, independent of whether the validator
  ran first. Down-only: the validator already owns gate/up type agreement, and
  YAGNI says don't duplicate it here.

- **D3 — Unit test via `DS4_TEST_HOOKS` proves the fix.** Add a
  `DS4_TEST_HOOKS`-gated function `ds4_test_mellum_decode_contract_admission()`
  to `ds4.c` that sets `g_ds4_shape = DS4_SHAPE_MELLUM2`, builds a fake
  layer-0 weights struct (all twelve pointers non-NULL; gate/up/down with real
  dims), and asserts the binder accepts `Q8_0` down and rejects `Q5_0` (9),
  `MXFP4` (39), and `Q4_K` (12). A new `tests/test_mellum_admission.c` links
  `ds4_cpu_test_hooks.o` and calls it. Pre-fix this test fails (Q5_0/MXFP4 are
  accepted; Q4_K dies); post-fix it passes.

- **D4 — Loader test with a real, committed, crafted artifact.** Commit a Python
  generator `tests/gen_mellum_admission_gguf.py` that emits a sparse,
  single-layer (layer 1) Mellum GGUF: full GGUF v3 header, `general.architecture
  = "mellum"`, every `mellum.*` key with its exact value (below), the 28-entry
  sliding-window pattern, and layer 1's twelve tensors with correct
  names/dims/types — with `ffn_down_exps` set to Q8_0 (good) or Q5_0 (bad) via a
  `--down-type` switch. All tensor `rel_offset`s are 0 and the file is truncated
  to cover the largest tensor (sparse ⇒ ~Kib on disk, ~140 MiB logical). A C
  driver `tests/drive_mellum_admission.c` opens the fixture through
  `ds4_engine_open` with `inspect_only=true`, `load_slice=true`,
  `load_layer_start=1`, `load_layer_end=1`, `backend=DS4_BACKEND_CPU`. A
  `test-mellum-admission` Makefile target asserts: good → exit 0; bad → exit ≠ 0
  and stderr contains `only Q8_0 is supported`. The 10–12 GiB research artifacts
  remain an optional manual gate (env-var driven), not a CI requirement.

- **D5 — SwiftStar pin bump, no Swift code.** In a fresh SwiftStar worktree,
  branch `p12-2-mellum-loadable`, fetch the pushed ds4 branch into
  `external/ds4`, check out the merge commit, and commit the submodule pointer
  bump. Nothing else changes.

## Exact constants for the crafted GGUF (from `DS4_SHAPE_MELLUM2`)

Metadata keys and values (types: `u32`/`u64`/`f32`/`string`/`bool[]`):

| key | value |
|-----|-------|
| `general.architecture` | `"mellum"` (string) |
| `general.alignment` | `32` (u32) |
| `mellum.block_count` | `28` (u32) |
| `mellum.context_length` | `131072` (u64) |
| `mellum.embedding_length` | `2304` (u32) |
| `mellum.feed_forward_length` | `7168` (u32) |
| `mellum.attention.head_count` | `32` (u32) |
| `mellum.attention.head_count_kv` | `4` (u32) |
| `mellum.attention.key_length` | `128` (u32) |
| `mellum.attention.value_length` | `128` (u32) |
| `mellum.expert_count` | `64` (u32) |
| `mellum.expert_used_count` | `8` (u32) |
| `mellum.expert_feed_forward_length` | `896` (u32) |
| `mellum.attention.sliding_window` | `1024` (u32) |
| `mellum.attention.sliding_window_pattern` | `bool[28]`, `pattern[i] = ((i & 3) != 3)` |
| `mellum.rope.scaling.type` | `"yarn"` (string) |
| `mellum.rope.scaling.original_context_length` | `8192` (u64) |
| `mellum.rope.scaling.factor` | `16.0` (f32) |
| `mellum.rope.scaling.yarn_attn_factor` | `1.2772589` (f32) |
| `mellum.rope.scaling.yarn_beta_fast` | `32.0` (f32) |
| `mellum.rope.scaling.yarn_beta_slow` | `1.0` (f32) |
| `mellum.rope.freq_base` | `500000.0` (f32) |
| `mellum.rope.freq_base_swa` | `500000.0` (f32) |
| `mellum.attention.layer_norm_rms_epsilon` | `1.0e-6` (f32) |

Layer-1 tensors (name, GGUF type id, dims):

| tensor | type | dims |
|--------|------|------|
| `blk.1.attn_norm.weight` | F32 (0) | `[2304]` |
| `blk.1.attn_q.weight` | Q8_0 (8) | `[2304, 4096]` |
| `blk.1.attn_q_norm.weight` | F32 (0) | `[128]` |
| `blk.1.attn_k.weight` | Q8_0 (8) | `[2304, 512]` |
| `blk.1.attn_k_norm.weight` | F32 (0) | `[128]` |
| `blk.1.attn_v.weight` | Q8_0 (8) | `[2304, 512]` |
| `blk.1.attn_output.weight` | Q8_0 (8) | `[4096, 2304]` |
| `blk.1.ffn_norm.weight` | F32 (0) | `[2304]` |
| `blk.1.ffn_gate_inp.weight` | F32 (0) | `[2304, 64]` |
| `blk.1.ffn_gate_exps.weight` | Q8_0 (8) | `[2304, 896, 64]` |
| `blk.1.ffn_up_exps.weight` | Q8_0 (8) | `[2304, 896, 64]` |
| `blk.1.ffn_down_exps.weight` | **Q8_0 (8) good / Q5_0 (9) bad** | `[896, 2304, 64]` |

GGUF v3 wire format (little-endian): `magic u32 = 0x46554747`, `version u32 =
3`, `n_tensors u64`, `n_kv u64`; each metadata entry = string key (u64 len +
bytes) + u32 type + value (scalar = raw; string = u64 len + bytes; array = u32
item-type + u64 len + items); each tensor = string name (u64 len + bytes) + u32
ndim + ndim×u64 dims + u32 type + u64 rel_offset; tensor data begins at
`align_up(end_of_directory, 32)`.

## Verification (acceptance)

1. The merged branch builds and passes `make test` in the ds4 worktree.
2. `ds4_test_mellum_decode_contract_admission()` passes (binder rejects Q5_0,
   MXFP4, Q4_K down; accepts Q8_0).
3. `make test-mellum-admission` passes: the good crafted GGUF opens (exit 0),
   the bad one is refused (exit ≠ 0, `only Q8_0 is supported`).
4. The merge commit is a real merge (two parents) pushed to `pauleveritt/ds4`;
   no rebase, no force-push.
5. SwiftStar's `external/ds4` submodule points at the merge commit on branch
   `p12-2-mellum-loadable`.
