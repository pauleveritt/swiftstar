# P12.2 Make Mellum Loadable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile the ds4 `swiftstar-integration-mellum` lineage (`cde6438`) with the pinned `laguna-think-budget` lineage (`1f9a4c5`), harden the Mellum admission contract against non-Q8_0 down tensors, prove it with a unit test and a crafted-artifact loader test, and bump SwiftStar's submodule pin.

**Architecture:** One ds4 branch (`swiftstar-integration-mellum-think-budget`) holds a real merge commit, a one-line hardening fix in `ds4_engine_bind_mellum_decode_contract`, and the tests. A fresh SwiftStar worktree then advances the `external/ds4` submodule pointer to that merge commit. No Swift code changes.

**Tech Stack:** C99 (ds4), GNU Make, Python 3 (stdlib only), git worktrees.

**Spec:** [`docs/superpowers/specs/2026-08-25-p12-2-mellum-loadable-design.md`](../specs/2026-08-25-p12-2-mellum-loadable-design.md) — the plan argues from the spec's decisions D1–D5; executors read both.

## Global Constraints

- Work happens in `~/projects/ds4` (has both lineages fetched). Do **not** work in the SwiftStar submodule checkout `Sources/../external/ds4` for the C-engine merge — it only has the pin.
- No rebase, no force-push, no history rewrite anywhere. The reconciliation is a real merge commit (two parents) with the fix and tests as later commits on the same branch.
- Push target for the ds4 branch is the `pauleveritt` remote (`pauleveritt/ds4`), never `origin` (`antirez/ds4`).
- The fix is exactly one line, placed **before** `layer_gate_down_expert_bytes`: `if (src->ffn_down_exps->type != DS4_TENSOR_Q8_0) return false;`.
- All new C test code compiles under `-std=c99 -Wall -Wextra` with no new warnings.
- macOS is the build host: `make` is the Metal build; `make cpu` is the `-DDS4_NO_GPU` build. Test hooks link `ds4_cpu_test_hooks.o` (ds4.c with `-DDS4_NO_GPU -DDS4_TEST_HOOKS`).

---

### Task 1: Reconcile the two ds4 lineages with a real merge

**Files:**
- Create: worktree `~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum-tb` (branch `swiftstar-integration-mellum-think-budget`)
- Modify (only if conflicts): `ds4.c`, `ds4_agent.c`, `ds4_server.c`, `ds4.h`, `Makefile`, `tests/*` — reconcile, preserving both lineages

**Interfaces:**
- Produces: branch `swiftstar-integration-mellum-think-budget` with a merge commit whose parents are `cde6438` and `1f9a4c5`, building cleanly. Later tasks commit on top of this branch.

- [ ] **Step 1: Create the worktree and branch at cde6438**

```bash
cd ~/projects/ds4
git worktree add -b swiftstar-integration-mellum-think-budget \
  .claude/worktrees/swiftstar-integration-mellum-tb cde6438
cd .claude/worktrees/swiftstar-integration-mellum-tb
git rev-parse HEAD   # expect cde6438bcd779e8720a9bddfcac6dabcd773efeb
```

- [ ] **Step 2: Merge the pinned lineage**

```bash
git merge 1f9a4c5423a045c0d642e8ba9bb24ac7d9250e6c
```

Expected: a merge commit. If git reports conflicts, proceed to Step 3; otherwise skip to Step 4.

- [ ] **Step 3: Resolve conflicts (if any)**

For each conflicted file, inspect both sides (`git diff cde6438...<file>` and `git diff 1f9a4c5...<file>`). Reconciliation rules:

- **Generic agent/tooling files** (`ds4_agent.c`, `ds4_server.c`, `ds4_cli.c`, json-events fixes, host-tools, consent flags): the think-budget side carries the canonical newer version; keep its behavior, but do not drop Mellum-specific additions the other side introduced.
- **Mellum-specific files** (Mellum quantization/kernel wiring, layer-major prefill, `ds4-server` Mellum hosting, Mellum tool-call-syntax recovery): keep the Mellum side.
- **`ds4.c`**: keep both — especially the Mellum decode-contract and `weights_validate_mellum_layout` regions (the hardening in Task 2 touches the former).

After editing each file: `git add <file>`. When all conflicts are staged: `git commit` (completes the merge).

- [ ] **Step 4: Build to confirm the reconciliation compiles**

```bash
make -j8
```

Expected: builds `ds4`, `ds4-server`, `ds4-bench`, `ds4-eval`, `ds4-agent` with no errors. If the Metal toolchain is unavailable on this host, fall back to `make cpu -j8` for verification and note it in the commit message.

- [ ] **Step 5: Sanity-check the admission-contract region survived the merge**

```bash
git grep -n "ds4_engine_bind_mellum_decode_contract\|weights_validate_mellum_layout" -- ds4.c
```

Expected: both symbols present; `ds4_engine_bind_mellum_decode_contract` still has the `if (src->ffn_gate_exps->type == DS4_TENSOR_Q4_K)` gate-only check (this is what Task 2 hardens).

- [ ] **Step 6: Commit the merge is already done (the merge commit is created by `git merge`)**

Confirm the merge commit has two parents:

```bash
git log --oneline -1 --pretty='%h parents=%p'
```

Expected: two parent hashes shown (one is `cde6438`, the other `1f9a4c5`).

---

### Task 2: Harden the admission contract + unit test (TDD)

**Files:**
- Modify: `ds4.c` (add the one-line fix in `ds4_engine_bind_mellum_decode_contract`; add a `DS4_TEST_HOOKS` test function)
- Modify: `ds4.h` (declare the test hook under `#ifdef DS4_TEST_HOOKS`)
- Create: `tests/test_mellum_admission.c`
- Modify: `Makefile` (build + run targets)

**Interfaces:**
- Produces: `int ds4_test_mellum_decode_contract_admission(void)` returning 0 on success, nonzero on failure. Later tasks do not consume it; it is the unit gate for the fix.

- [ ] **Step 1: Add the test hook to ds4.c (the failing test's subject)**

Insert into `ds4.c`, inside the existing `#ifdef DS4_TEST_HOOKS` region (near `ds4_test_make_engine`, ~line 61568):

```c
#ifdef DS4_TEST_HOOKS
int ds4_test_mellum_decode_contract_admission(void) {
    g_ds4_shape = DS4_SHAPE_MELLUM2;

    ds4_tensor t[12];
    memset(t, 0, sizeof(t));

    ds4_engine e;
    memset(&e, 0, sizeof(e));
    ds4_layer_weights *lw = &e.weights.layer[0];

    lw->attn_norm     = &t[0];
    lw->attn_q        = &t[1];
    lw->attn_q_norm   = &t[2];
    lw->attn_k        = &t[3];
    lw->attn_k_norm   = &t[4];
    lw->attn_v        = &t[5];
    lw->attn_output   = &t[6];
    lw->ffn_norm      = &t[7];
    lw->ffn_gate_inp  = &t[8];
    lw->ffn_gate_exps = &t[9];
    lw->ffn_up_exps   = &t[10];
    lw->ffn_down_exps = &t[11];

    ds4_tensor *gate = &t[9], *up = &t[10], *down = &t[11];
    gate->type = up->type = DS4_TENSOR_Q8_0;
    gate->ndim = up->ndim = down->ndim = 3;
    gate->dim[0] = DS4_N_EMBD;  gate->dim[1] = DS4_N_FF_EXP; gate->dim[2] = DS4_N_EXPERT;
    up->dim[0]   = DS4_N_EMBD;  up->dim[1]   = DS4_N_FF_EXP; up->dim[2]   = DS4_N_EXPERT;
    down->dim[0] = DS4_N_FF_EXP; down->dim[1] = DS4_N_EMBD;  down->dim[2] = DS4_N_EXPERT;

    int failures = 0;

    down->type = DS4_TENSOR_Q8_0;
    if (!ds4_engine_bind_mellum_decode_contract(&e, 0, 0)) {
        fprintf(stderr, "mellum admission: Q8_0 down unexpectedly rejected\n");
        failures++;
    }

    /* MXFP4 first: it is the one type the un-fixed binder silently accepts. */
    down->type = DS4_TENSOR_MXFP4;
    if (ds4_engine_bind_mellum_decode_contract(&e, 0, 0)) {
        fprintf(stderr, "mellum admission: MXFP4 down unexpectedly accepted\n");
        failures++;
    }

    down->type = 6; /* GGUF Q5_0: what official mixed artifacts use for down */
    if (ds4_engine_bind_mellum_decode_contract(&e, 0, 0)) {
        fprintf(stderr, "mellum admission: Q5_0 down unexpectedly accepted\n");
        failures++;
    }

    down->type = DS4_TENSOR_Q4_K;
    if (ds4_engine_bind_mellum_decode_contract(&e, 0, 0)) {
        fprintf(stderr, "mellum admission: Q4_K down unexpectedly accepted\n");
        failures++;
    }

    return failures;
}
#endif
```

- [ ] **Step 2: Declare the hook in ds4.h**

In `ds4.h`, inside the existing `#ifdef DS4_TEST_HOOKS` block (near `ds4_test_sample_logits`, ~line 573):

```c
int ds4_test_mellum_decode_contract_admission(void);
```

- [ ] **Step 3: Write the test file**

Create `tests/test_mellum_admission.c`:

```c
#include "ds4.h"
#include <stdio.h>

int main(void) {
    int failures = ds4_test_mellum_decode_contract_admission();
    if (failures) {
        fprintf(stderr, "mellum admission: %d failure(s)\n", failures);
        return 1;
    }
    puts("mellum admission: ok");
    return 0;
}
```

- [ ] **Step 4: Add Makefile build + run rules**

In `Makefile`, next to the `ds4_cpu_test_hooks.o` rule:

```make
tests/test_mellum_admission.o: tests/test_mellum_admission.c ds4.h
	$(CC) $(CFLAGS) -DDS4_TEST_HOOKS -I. -c -o $@ tests/test_mellum_admission.c

tests/test_mellum_admission: tests/test_mellum_admission.o ds4_cpu_test_hooks.o ds4_distributed.o ds4_tp.o ds4_ssd.o ds4_layer_pack.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)
```

- [ ] **Step 5: Run the test, confirm it FAILS (red)**

```bash
make tests/test_mellum_admission && ./tests/test_mellum_admission
```

Expected: FAIL (red) — pre-fix the binder returns true for MXFP4 down (prints `MXFP4 down unexpectedly accepted`), then the Q5_0 case `ds4_die`s ("unsupported routed expert tensor type"), so the process exits nonzero. The die is the bug manifesting; the fix turns both into clean `return false`.

- [ ] **Step 6: Apply the one-line fix**

In `ds4.c`, in `ds4_engine_bind_mellum_decode_contract`, immediately after `if (!weights_mellum_layer_has_required(src)) return false;` and **before** the `if (src->ffn_gate_exps->type == DS4_TENSOR_Q4_K)` line, add:

```c
        if (src->ffn_down_exps->type != DS4_TENSOR_Q8_0) return false;
```

- [ ] **Step 7: Run the test, confirm it PASSES (green)**

```bash
make tests/test_mellum_admission && ./tests/test_mellum_admission
```

Expected: `mellum admission: ok`, exit 0.

- [ ] **Step 8: Commit**

```bash
git add ds4.c ds4.h tests/test_mellum_admission.c Makefile
git commit -m "mellum: reject non-Q8_0 down tensors in decode contract"

# note: tests/test_mellum_admission is a build artifact; ensure it's not committed
# (it should already be ignored; if not, add it to .gitignore in the same commit)
```

---

### Task 3: Crafted-artifact loader test

**Files:**
- Create: `tests/gen_mellum_admission_gguf.py`
- Create: `tests/drive_mellum_admission.c`
- Modify: `Makefile` (driver build rule + `test-mellum-admission` target)

**Interfaces:**
- Produces: `make test-mellum-admission` runs the whole loader gate (good fixture opens; bad fixture refused). No later task consumes it; it is the acceptance evidence for D4.

- [ ] **Step 1: Write the GGUF generator**

Create `tests/gen_mellum_admission_gguf.py`:

```python
#!/usr/bin/env python3
"""Emit a sparse, single-layer (layer 1) Mellum GGUF for the admission test.

--down-type q8_0 is the valid fixture; q5_0 is the invalid one the loader must
refuse. Only header + metadata + tensor directory are written; the payload is a
sparse hole (never read during admission), so the file is ~Kib on disk.
"""
import argparse
import struct

MAGIC = 0x46554747          # "GGUF", little-endian
VERSION = 3
ALIGN = 32

UINT8, INT8, UINT16, INT16, UINT32, INT32, FLOAT32, BOOL, STRING, ARRAY, UINT64, INT64, FLOAT64 = range(13)
F32, Q8_0, Q5_0 = 0, 8, 6


def s(b):
    data = b.encode() if isinstance(b, str) else b
    return struct.pack("<Q", len(data)) + data


def kv(key, vtype, payload):
    return s(key) + struct.pack("<I", vtype) + payload


def p_u32(v): return struct.pack("<I", v)
def p_u64(v): return struct.pack("<Q", v)
def p_f32(v): return struct.pack("<f", v)


def tensor(name, ndim, dims, ttype):
    return (s(name) + struct.pack("<I", ndim) +
            b"".join(struct.pack("<Q", d) for d in dims) +
            struct.pack("<I", ttype) + struct.pack("<Q", 0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--down-type", choices=("q8_0", "q5_0"), required=True)
    a = ap.parse_args()
    down_type = Q8_0 if a.down_type == "q8_0" else Q5_0

    pattern = bytes(1 if ((i & 3) != 3) else 0 for i in range(28))

    meta = [
        kv("general.architecture", STRING, s("mellum")),
        kv("general.alignment", UINT32, p_u32(ALIGN)),
        kv("mellum.block_count", UINT32, p_u32(28)),
        kv("mellum.context_length", UINT64, p_u64(131072)),
        kv("mellum.embedding_length", UINT32, p_u32(2304)),
        kv("mellum.feed_forward_length", UINT32, p_u32(7168)),
        kv("mellum.attention.head_count", UINT32, p_u32(32)),
        kv("mellum.attention.head_count_kv", UINT32, p_u32(4)),
        kv("mellum.attention.key_length", UINT32, p_u32(128)),
        kv("mellum.attention.value_length", UINT32, p_u32(128)),
        kv("mellum.expert_count", UINT32, p_u32(64)),
        kv("mellum.expert_used_count", UINT32, p_u32(8)),
        kv("mellum.expert_feed_forward_length", UINT32, p_u32(896)),
        kv("mellum.attention.sliding_window", UINT32, p_u32(1024)),
        kv("mellum.attention.sliding_window_pattern", ARRAY,
           struct.pack("<I", BOOL) + struct.pack("<Q", 28) + pattern),
        kv("mellum.rope.scaling.type", STRING, s("yarn")),
        kv("mellum.rope.scaling.original_context_length", UINT64, p_u64(8192)),
        kv("mellum.rope.scaling.factor", FLOAT32, p_f32(16.0)),
        kv("mellum.rope.scaling.yarn_attn_factor", FLOAT32, p_f32(1.2772589)),
        kv("mellum.rope.scaling.yarn_beta_fast", FLOAT32, p_f32(32.0)),
        kv("mellum.rope.scaling.yarn_beta_slow", FLOAT32, p_f32(1.0)),
        kv("mellum.rope.freq_base", FLOAT32, p_f32(500000.0)),
        kv("mellum.rope.freq_base_swa", FLOAT32, p_f32(500000.0)),
        kv("mellum.attention.layer_norm_rms_epsilon", FLOAT32, p_f32(1.0e-6)),
    ]

    tensors = [
        tensor("blk.1.attn_norm.weight", 1, [2304], F32),
        tensor("blk.1.attn_q.weight", 2, [2304, 4096], Q8_0),
        tensor("blk.1.attn_q_norm.weight", 1, [128], F32),
        tensor("blk.1.attn_k.weight", 2, [2304, 512], Q8_0),
        tensor("blk.1.attn_k_norm.weight", 1, [128], F32),
        tensor("blk.1.attn_v.weight", 2, [2304, 512], Q8_0),
        tensor("blk.1.attn_output.weight", 2, [4096, 2304], Q8_0),
        tensor("blk.1.ffn_norm.weight", 1, [2304], F32),
        tensor("blk.1.ffn_gate_inp.weight", 2, [2304, 64], F32),
        tensor("blk.1.ffn_gate_exps.weight", 3, [2304, 896, 64], Q8_0),
        tensor("blk.1.ffn_up_exps.weight", 3, [2304, 896, 64], Q8_0),
        tensor("blk.1.ffn_down_exps.weight", 3, [896, 2304, 64], down_type),
    ]

    header = (struct.pack("<I", MAGIC) + struct.pack("<I", VERSION) +
              struct.pack("<Q", len(tensors)) + struct.pack("<Q", len(meta)))
    body = b"".join(meta) + b"".join(tensors)
    dir_end = len(header) + len(body)
    data_pos = (dir_end + ALIGN - 1) // ALIGN * ALIGN

    # Largest tensor byte span (gate/up/down, 2304*896*64 elements). Q8_0 packs
    # 32 elements per 34 bytes → ~134 MiB; Q5_0 packs 32 per 22 bytes → ~87 MiB.
    # Over-cover with 2x (sparse, so disk cost is negligible).
    max_bytes = 2304 * 896 * 64 * 2
    total = data_pos + max_bytes

    with open(a.out, "wb") as f:
        f.write(header)
        f.write(body)
        f.write(b"\x00" * (data_pos - dir_end))
        f.truncate(total)
    print(f"wrote {a.out} ({total} logical bytes, sparse)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Write the admission driver**

Create `tests/drive_mellum_admission.c`:

```c
#include "ds4.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s MODEL.gguf\n", argv[0]);
        return 2;
    }
    ds4_engine_options opt;
    memset(&opt, 0, sizeof(opt));
    opt.model_path = argv[1];
    opt.backend = DS4_BACKEND_CPU;
    opt.inspect_only = true;
    opt.load_slice = true;
    opt.load_layer_start = 1;
    opt.load_layer_end = 1;
    opt.load_output = false;

    ds4_engine *e = NULL;
    int rc = ds4_engine_open(&e, &opt);
    if (rc != 0) {
        fprintf(stderr, "ds4_engine_open failed (rc=%d)\n", rc);
        return 1;
    }
    ds4_engine_close(e);
    printf("ADMISSION_OK\n");
    return 0;
}
```

- [ ] **Step 3: Add Makefile rules**

In `Makefile`, next to the Task 2 rules:

```make
tests/drive_mellum_admission.o: tests/drive_mellum_admission.c ds4.h
	$(CC) $(CFLAGS) -I. -c -o $@ tests/drive_mellum_admission.c

tests/drive_mellum_admission: tests/drive_mellum_admission.o ds4_cpu.o ds4_distributed.o ds4_tp.o ds4_ssd.o ds4_layer_pack.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

test-mellum-admission: tests/test_mellum_admission tests/drive_mellum_admission
	./tests/test_mellum_admission
	python3 tests/gen_mellum_admission_gguf.py --out /tmp/mellum-adm-good.gguf --down-type q8_0
	python3 tests/gen_mellum_admission_gguf.py --out /tmp/mellum-adm-bad.gguf --down-type q5_0
	./tests/drive_mellum_admission /tmp/mellum-adm-good.gguf
	@if ./tests/drive_mellum_admission /tmp/mellum-adm-bad.gguf >/dev/null 2>/tmp/mellum-adm-bad.err; then \
	  echo "mellum admission: bad fixture was NOT refused" >&2; exit 1; \
	fi
	@grep -q "only Q8_0 is supported" /tmp/mellum-adm-bad.err || { \
	  echo "mellum admission: refusal did not name the down-tensor limit" >&2; \
	  cat /tmp/mellum-adm-bad.err >&2; exit 1; }
	@echo "mellum admission: loader gate ok"
```

Also add `test-mellum-admission` to the `.PHONY` list at the top of `Makefile`.

- [ ] **Step 4: Run the loader gate, confirm it passes**

```bash
make test-mellum-admission
```

Expected: `mellum admission: ok`, then `ADMISSION_OK` for the good fixture, then `mellum admission: loader gate ok`. Exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/gen_mellum_admission_gguf.py tests/drive_mellum_admission.c Makefile
git commit -m "mellum: crafted-artifact admission loader test"
```

---

### Task 4: Push the ds4 branch

**Files:** none (git remote ref update)

- [ ] **Step 1: Full verification before push**

```bash
make -j8
make test-mellum-admission
```

Expected: build clean; loader gate ok. (If the full Metal `make` is not runnable on this host, `make cpu -j8` + `make test-mellum-admission` is acceptable, and note it.)

- [ ] **Step 2: Push to the fork (never origin)**

```bash
git push -u pauleveritt swiftstar-integration-mellum-think-budget
```

Expected: new branch on `pauleveritt/ds4`. Record the resulting commit hash:

```bash
git rev-parse HEAD
```

---

### Task 5: Bump the SwiftStar submodule pin

**Files:**
- Modify: `external/ds4` (submodule pointer) in the SwiftStar repo

- [ ] **Step 1: Create a SwiftStar worktree and branch**

```bash
cd /Users/pauleveritt/projects/pauleveritt/swiftstar
git worktree add -b p12-2-mellum-loadable .worktrees/p12-2-mellum-loadable
cd .worktrees/p12-2-mellum-loadable
```

- [ ] **Step 2: Advance the submodule to the merge commit**

```bash
cd external/ds4
git fetch https://github.com/pauleveritt/ds4.git swiftstar-integration-mellum-think-budget
git checkout FETCH_HEAD
cd ..
```

Expected: `external/ds4` HEAD is the Task 4 merge commit (two-parent merge with the fix + tests).

- [ ] **Step 3: Verify the submodule points at the intended commit and commit**

```bash
git -C external/ds4 rev-parse HEAD   # confirm matches Task 4's rev-parse output
git add external/ds4
git commit -m "Pin ds4 to Mellum-loadable merge (P12.2)"
```

- [ ] **Step 4: Sanity check the submodule is clean and builds nothing extra**

```bash
git status --short
git diff --stat HEAD~1
```

Expected: only `external/ds4` changed (one line: the new submodule SHA).

- [ ] **Step 5: Push the SwiftStar branch**

```bash
git push -u origin p12-2-mellum-loadable
```

---

## Self-review notes

- D1 → Task 1; D2 → Task 2 Step 6; D3 → Task 2; D4 → Task 3; D5 → Task 5.
- No placeholders: every code step has full code; every command has its expected output.
- Type consistency: the test hook returns `int` (failure count); the test file and Makefile both call `ds4_test_mellum_decode_contract_admission()` declared in `ds4.h`; the driver links `ds4_cpu.o` (public `ds4_engine_open`/`ds4_engine_close`, both declared in `ds4.h`).
- Risks to watch during execution: (a) the merge may surface conflicts in `ds4.c`/agent files — resolve per the Task 1 rules; (b) `ds4_backend_uses_graph(DS4_BACKEND_CPU)` must be false so `model_open` takes the CPU non-prefetch path — if `inspect_only` still prefetches, the sparse payload would be read and the driver would still pass because holes read as zeros, but the admission path itself is unaffected; (c) GGUF type 6 (Q5_0) is a known type (`gguf_types[6] = {"q5_0", 32, 22}`); `tensor_nbytes` computes its bytes (90,832,896 for the down tensor), well under the generator's 264 MiB cover. Refusal comes from `weights_validate_mellum_layout`'s explicit down-type check, not from byte math.
