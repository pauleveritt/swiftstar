# P11 agenttest — Laguna on the harder problem: preliminary analysis (2026-08-23)

**Status:** preliminary, n=1 per failure mode, from the captured wire
(`captures/agenttest/20260823-*-roadmap-user-story/wire.ndjson`). Three hard-spec
runs, three distinct-but-related failure signatures; one easy-spec comparison.

## The headline

The user-story spec does **not** defeat Laguna at planning — its opening
reasoning is a correct decomposition, and its first think-draft is a complete,
coherent implementation. It defeats Laguna at **convergence**: the model
redrafts that solution verbatim ~12 times inside its thinking, never emits a
tool call (2 of 3 runs), and dies mid-draft when the context hits 32,767.

## Evidence

| run | spec | think events | tool calls | text | end |
|---|---|---|---|---|---|
| 19:26 | hard | 5,738 | 21 | 47 | `stop=limit gen=12051 ctx=32767` |
| 19:42 | hard | 5,111 | 0 | 0 | (turn never ended — timeout) |
| 19:53 | hard | 7,464 | 0 | 0 | `stop=limit gen=31151 ctx=32767` |
| 19:24 | **easy** | **0** | 16 | — | acceptance green, DeepSeek "good" |

The 19:53 run generated **31,151 tokens for zero output** (0 tool calls, 0 text).
Its think stream is 122,512 chars: `"Actually"` ×69, `"OK"` ×68, `"Wait"` ×17,
`"Hmm"` ×18, and **12–13 complete drafts** of the whole file set
(`"### templates/base.html"` ×12, `"from fastapi import"` ×14).

## Finding 1 — the redrafts are verbatim

Extracted draft #1 and the last complete draft from the think stream and diffed
them: **byte-identical** (models.py 197 B, app.py 1147 B, base.html 760 B,
home.html 431 B, complaints.html 1044 B, test_app.py 2073 B). The
"deliberation" does not change the output — the model re-emits the identical
solution after each micro-reconsideration. This is a degenerate loop, not
engineering.

## Finding 2 — the one real defect is a hidden contract

Draft #1 fails the acceptance suite on exactly one point: the suite requires
`models.complaints` (the in-memory list must live in `models.py`); Laguna puts it
in `app.py`. The hard spec never says where the list lives; the easy spec pins it
explicitly ("Create a module-level list `complaints: list[Complaint]` in
`models.py`"). So 31k tokens of reconsideration never touched the only thing that
mattered, and the model had no way to discover it — its vetted self-test runs its
*own* tests, not the acceptance suite.

## Finding 3 — ambiguity converts directly into think-tokens

The tool budget (30) bounds tool calls; nothing bounds thinking. The user-story
spec leaves every micro-decision open (quote handling in the tagline, timestamp
format, relative vs absolute template paths, test isolation, form validation),
and each open decision triggers a full redraft. The easy spec pins everything →
**zero think events**. This sharpens the local-ai-pi doctrine ("facts work, rules
of conduct do not"): for this model, *ambiguity → unbounded deliberation →
context death*.

## Finding 4 — it is not hard-spec-exclusive

The 32k batch on the **easy** spec reproduced the same think-loop: runs 1 and 2
both ended `stop=limit` (gen 31,053 / 18,872, ctx 32,767) with **no grade**,
whereas the pre-revert 16k easy runs passed in ~2 min at ~9k ctx, and the 19:24
easy run passed at 32k with 0 think events. So the think-loop is a general
Laguna failure mode that ambiguity makes near-certain, and a larger context just
scales the damage (31k wasted tokens instead of ~16k).

## Secondary pathology (19:26 run, which did act)

It first burned **6 writes on absolute paths** (`/Users/pauleveritt/projects/...`
— refused: outside the workspace grant), likely primed by the prompt's vetted
commands carrying absolute paths (`uv run --project /Users/...`). It recovered,
completed phase 1, then died of session exhaustion in phase 2 (the pooled worker
session cannot compact for the next phase).

## Levers (next work, in order)

1. **Facts, not rules** (harness-side): a decision sheet in the packet — where
   the in-memory list lives, timestamp format, "paths are workspace-relative",
   quote handling. Removes the deliberation triggers and the hidden-contract trap.
2. **Bound think-tokens** (engine-side, ds4): a think-token budget analogous to
   the tool budget — the only real bound on the loop. Until this exists, any
   ambiguity is potentially unbounded.
3. **Let the self-test see the acceptance contract** (harness-side): the vetted
   pytest command should run the acceptance suite, not the worker's own tests, so
   the model can discover the real contract instead of redrafting blind.

## Update — n=4 easy-spec batch baseline (pre-fix, 32k)

The `--batch 4` run on the **easy** spec (before the fixes) finished 3 of 4
runs before being interrupted mid-run-4:

| run | outcome |
|---|---|
| 1 | think-loop → `limit` (gen 31,053), no grade |
| 2 | think-loop → `limit` (gen 18,872), no grade |
| 3 | **pass** — 3 phases eos (ctx 8.7k→14.3k→21.8k), acceptance + DeepSeek "good" |
| 4 | interrupted mid-turn (was progressing, 5 tool calls — not looping) |

So at 32k the easy spec passes roughly 1 in 3, with the other runs think-looping
to the context limit. The fixes applied next: (1) a per-round `-n 8192` token cap
(bounds a think-loop before it fills the context), (2) the hard spec now pins the
data-model contract (`Complaint` fields, timezone-aware `timestamp`,
`models.complaints`) via a preamble that reaches every packet, and (3) the packet
now states tool paths are workspace-relative (the 19:26 run's absolute-path
waste).

## Resolution — what fixed it (2026-08-23)

The loop is "can't stop deliberating," not "missing a fact." Pin a fact and the
model moves its deliberation to the next open sub-question (after pinning the
list location, it obsessed over timestamp uniqueness — 30 `timezone`/28
`default_factory` mentions). The fixes that worked, in combination:

1. **`--nothink` (the decisive one).** Disabling the reasoning phase makes the
   worker emit tool calls directly instead of think-looping. With the contract
   facts pinned in the spec, it does not need to deliberate — it just executes
   (the "model is only the implementer" posture from D1). This is now the
   agent-test default (`AGENTTEST_THINK=1` re-enables reasoning for comparison).
2. **Complete contract facts.** The spec now pins every detail the acceptance
   suite checks that the user-story omitted: the `Complaint` dataclass fields,
   the timezone-aware `default_factory` timestamp, `models.complaints`, and the
   **Bootstrap `.card`** rendering (the `--nothink` run failed 12/13 on exactly
   that last one — `document.select(".card")` found 0).
3. **`-n 8192`** bounds any residual loop (a think-loop now stops at 8192 tokens
   in ~2 min instead of 31k tokens / context exhaustion).
4. **Grader fence parse.** DeepSeek returns ```json-fenced output despite the
   prompt; the parser now reads the first `{`..last `}`.

### Final result (n=1 each)

| spec | before | after |
|---|---|---|
| easy | 1/3 pass (2 think-loops), ~2–14 min | **pass**, acceptance + DeepSeek "good", ~2 min |
| hard | 0/3 (think-loop → `noChanges`) | **pass**, acceptance exit 0 + DeepSeek "good" (9 reasons), 210s |

Hard spec after: 16 tool calls (10/3/3), 6/3/3 mutations, ctx 4.5k→7.4k→10.9k,
no re-reads, no repeated-identical calls. The remaining follow-up is n=4 for a
rate, and the model-variance question (does `--nothink` hold up across seeds?)
that only a batch answers.
