# Laguna S revision test — spec (2026-08-24)

> **Superseded as a live finding** by [`2026-08-25-local-model-agency.md`](2026-08-25-local-model-agency.md). Retained as the evidence record for the hand-holding-ladder (L1-L3) experiment design gating whether the repair role can revise its own output.

**Status:** specification only. Nothing run. This is the gate experiment for the
three-role thinking pipeline; nothing downstream should be built before it
reports.

## The question

**Does Laguna S, shown a concrete failure and the offending line, emit text that
differs from its input?**

Not "does it fix the bug." Does the text *change at all*. Correctness is a
secondary metric; the primary measurement is a diff.

## Why this gates everything

The target architecture needs thinking at three points — decompose, implement,
repair. The repair role is the only one that requires the model to *revise* prior
output rather than produce fresh output. Two results in the corpus suggest that
capability may not exist:

- Laguna redrafts **byte-identically** inside its own thinking: draft #1 and the
  last complete draft diffed clean across six files
  ([hard analysis](2026-08-23-p11-agenttest-laguna-hard-analysis.md):30–36).
- Mellum re-emitted an entire 3.8K file **byte-for-byte** after being shown its
  own offending line and the verbatim `ImportError` naming the exact symbol
  (`mellum-repair-pipeline` record, "The round-4 re-test").

Same signature, different scope. If Laguna shares the pathology, the repair role
has no floor and the third thinking point does not exist — which changes the
architecture, not just its tuning. That is worth one cheap experiment before any
engine work.

## Design — the hand-holding ladder

A binary "did it revise" answer is nearly useless: a null result can't
distinguish *can't diagnose* from *can't apply an instruction*. So the model gets
the same file and the same output contract at three escalating levels of
hand-holding, and we find the level at which revision starts.

| level | what the model is given | failure at this level means |
|---|---|---|
| **L1** | real pytest failure output + full file content | can't localize a fault from machine evidence |
| **L2** | L1 + the offending line quoted verbatim | can't connect a named error to a named line |
| **L3** | L2 + the fix stated in prose (*"`RedirectResponse` lives in `fastapi.responses`"*) | **pure echo pathology** — can't apply a stated instruction |

L3 is the floor. A model that returns identical text when told exactly what to
change is not performing revision under any definition, and no amount of
better-localized host evidence will rescue it.

L2 reproduces Mellum's round-4 condition exactly, which makes the two models
directly comparable.

## Conditions

**Primary arm — Laguna S Q4_K_M, thinking ON, temp 0.**
`~/projects/ds4/.claude/worktrees/laguna-s-bench/gguf/laguna-s-2.1-Q4_K_M.gguf`

Q4_K_M rather than Q2_K because the requirement is thinking, and Q2_K + thinking
is already documented as unreliable (~0/5 acting). Testing revision on a config
we already know is broken would confound the two failures.

3 levels × 2 bugs × n=3 = 18 runs.

**Temp arm — same cells at temp 0.7, run only where temp 0 returned identical
text.** At `--temp 0` a single run reports the mode of the distribution, not the
distribution. If temp 0.7 produces varied-but-still-unfixed output, the finding
is "can't diagnose." If it produces the fix sometimes, the finding is "temp 0 is
the wrong sampling config for the repair role" — actionable, and cheap to miss.

**Quant arm — Q2_K, sequenced after Q4_K_M, not demoted by it.** Q2_K is the
target that actually matters: it fits the 55 GiB envelope natively, with no
SSD streaming and none of its ~42–48% decode/prefill penalty. It's tested
second, not because it's lower priority, but because Q2_K carries a known,
separate failure mode (~0/5 acting under thinking) that would confound a
revision measurement — a null at Q2 wouldn't distinguish "can't revise" from
"can't stop thinking long enough to revise." Q4 gets a clean answer to the
revision question specifically.

The real sequence: (1) does revision work at all, tested where the confound is
absent; (2) whatever termination control resolves the residual think-loop
(convergence detection, `-n`, or otherwise) gets applied to Q2_K, not just Q4;
(3) retest revision at Q2_K under that control. If it holds, Q2_K + control is
the likely ship target at 55 GiB — cheaper than Q4_K_M+SSD and without the S21
port dependency. Skip step 3 only on a Q4 null (no control to carry over).

## Bugs

Both are single-file, pre-diagnosed, and drawn from the existing fixtures so the
result is comparable to prior runs.

1. **`RedirectResponse` import** — `from fastapi import FastAPI, Form,
   RedirectResponse`, failing with `ImportError: cannot import name
   'RedirectResponse' from 'fastapi'`. This is Mellum's round-4 bug. Primary.
2. **Shared mutable default** — dataclass field needing `default_factory`, in
   `models.py`. This is the Result-2 near-miss bug Mellum *did* solve. Included
   so a null result can't be dismissed as bug-specific.

## The file picker is bypassed

`repair.py`'s `pick_target_file` scores candidates by traceback-substring match
and chose a non-broken file in **three** observed rounds, burning attempts. It is
a known-weak component and would confound a revision measurement with a routing
measurement. The target file is supplied directly at every level.

Fixing the picker is separate work and should not be bundled into this test.

## Measurement

Per run, recorded mechanically:

- **`sha256(returned_file) == sha256(input_file)`** — the primary metric.
- `difflib` line-delta count when it differs (a 1-line change and a full rewrite
  are different results).
- Real `pytest` exit code after the host writes the returned file — never the
  model's claim of success. Reuse `repair.py`'s `run_pytest`.
- **Think-stream telemetry**, which is where Laguna's pathology lives: think
  event count, `stop` reason, `generated`, and whether complete drafts *inside*
  the thinking are byte-identical to each other (same extraction technique the
  hard analysis used).

## Outcomes, named in advance

Stated before running so the result can't be rationalized afterward. Four
distinct outcomes, not two:

| outcome | reading | consequence |
|---|---|---|
| **Identical text at L3** | echo pathology confirmed | repair role is dead for Laguna; architecture drops to two thinking points, or repair moves to another model |
| **Identical at L1/L2, revises at L3** | diagnosis failure, not revision failure | repair role survives; the host must supply localized fixes, which raises what the *validate* step must produce |
| **Revises at L1** | revision works | build the three-role pipeline as designed |
| **Think-loops, emits nothing** | termination failure, not revision failure | **distinct from all of the above** — blocked on convergence detection, retest after |

That fourth row is the one most likely to be misread as a null. A run that never
emits has not answered the question.

## Confound being controlled

The prompt hands the model a file and asks for a file. That format *invites*
echo. Mellum's round-4 result did not control for this, and the L1→L3 ladder is
precisely the control: if the model echoes at L1 but revises at L3, the echo is
diagnosis-driven; if it echoes at L3 under an explicit instruction, the echo is
format-driven or pathological. Either way the ladder separates them.

One point in the Mellum result's favor, worth stating since it applies here too:
round 4's prompt *differed* from round 2's (it carried the extra error text), so
its byte-identical output is not explained by temp-0 determinism.

## Scripts

Reuse from `mellum-repair-pipeline/pipeline/`:

- `repair.py` — `run_pytest` (the only trusted ground truth) and the writable-file
  scope. The round loop and `pick_target_file` are **not** used.
- `repair_prompt_template.txt` — the output contract (one fenced block, path as
  info string, complete file, no prose) is already validated against a local
  model; L1 is essentially this template. L2/L3 add sections.

New:

- **`run_laguna.sh`** — fork of `run_mellum.sh` with `--nothink` **dropped**
  (thinking is the point) and think-stream capture added. Keep the Metal shader
  env export block and the `+DWARFSTAR_STATUS` stripping — both are load-bearing
  and non-obvious. Set a generous `-n` cap (16384) to bound a think-loop without
  pre-empting normal reasoning.
- **`revision_test.py`** — builds the L1/L2/L3 prompts, invokes per cell, records
  the metrics above, writes per-run prompt/output/think/pytest logs.

## Cost

18 primary runs. Generation is short (one file); *thinking* is the wildcard, so
worst case is every run hitting the 16384 cap at ~50 t/s ≈ 5.5 min, ~100 min for
the arm. Model reload is not a concern after the first load (residency dropped
4907 ms → 295 ms warm in the observed logs). Comfortably an overnight batch.

n=3 per cell is deliberate: every prior conclusion in this line of work was n=1,
and the reviewer critique specifically flagged rate claims resting on single
runs. n=3 does not give a rate either, but it distinguishes stable behavior from
one sample.
