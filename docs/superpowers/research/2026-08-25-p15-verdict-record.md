# P15 — host-controlled action mode: verdict record

*Measured 2026-08-25 on branch `p15-host-controlled-action-mode`. Commits
`423e6f7` (two-turn emission protocol; honest sampler/seed records), `1a8314a`
(lenient harvest, first-occurrence-wins, repeated-heading abort, shared by both
arms), `05a4fcc` (validation output capture).*

## The question P15 asked

Not "is Mellum shippable." P13 had already established that Mellum 2.1 reliably
fails SwiftStar's tool-call initiation gate under the tested harness. P15 asked
the narrower, decidable question: **is Mellum harness-addressable — does a
host-side fix reach it — or content-broken?**

The method removes tool initiation from the loop entirely. Under a `textContract`
packet the model is told not to call tools and to emit `#path` headings plus file
bodies as plain text; `LabeledBlockParser` harvests them, the host writes the
files and injects the paths into `TurnOutcome.mutations` so the existing verdict
machinery can produce a candidate, then validates and grades as usual.

## Verdict

**Harness-addressable.** Every failure mode this phase found was host-side, and
each one yielded to a host-side fix:

| Observed failure | Actual cause | Fix |
|---|---|---|
| Repair turn reasons, then stops at eos where the file should start | Mellum reasons *or* emits, never both in one turn | Two-turn emission protocol on the same pooled worker session |
| Build turn emits headings with no fenced body → `contractNotFollowed` | Parser required fences; the bodies were complete and EOS-terminated | Lenient harvest |
| Build turn runs to the 8192-token wall | Degenerate resampling after a complete pass | First-occurrence-wins + repeated-heading abort |
| Phase dies on an import check with no stated cause | `runValidation` hashed stdout and discarded it; the traceback is on stderr | Capture combined output; digest the same text |

Nothing in the phase required engine work, a sampler change, or a different
model. That is the answer.

**Scope of the claim.** This is *drafting quality plus host orchestration, not
agency* — the label every text-contract run carries in its `run-config.json` as
`resultClass`. Zero tool calls means the model never acted; every file was
written by the host. A reader who sees "13/13 on agentclinic" and infers agency
has misread it, which is precisely why the label is recorded in-band per run.

## Measured

**Repair arm** — 4/4 live runs reach 13/13 on the `plausible-wrong-fix` fixture.
The two-turn emission protocol fired in 3 of the 4 and rescued all three.

**Build arm** — **9 runs** after the harvest fix:

- **0 `contractNotFollowed`** across all 9 (previously 3 of 4 runs).
- **3 of 9 runs reach 13/13** on the real acceptance suite, all three phases,
  **0 tool calls**, 90–132s per passing run.
- No failure is a harvest failure. The observed taxonomy, now legible because
  `05a4fcc` captures validation output:

  | Cause | Runs | Class |
  |---|---|---|
  | `RuntimeError: Directory 'static' does not exist` (mounted `StaticFiles` on a dir not in the grant) | 1 | content |
  | `ImportError: cannot import name 'RedirectResponse' from 'fastapi'` (wrong module) | 2 | content |
  | `ImportError: attempted relative import with no known parent package` | 2 | content |
  | `ModuleNotFoundError: No module named 'app'` — turn stopped at `limit`, harvest gate requires `eos`, so nothing was written | 1 | stopping |

**Read the rate honestly.** An early 3-of-5 did not survive a larger sample; the
same discipline that dissolved "build arm 1/4" applies to its replacement. The
defensible claim is **Mellum can complete AgentClinic basic end-to-end, and does
so about a third of the time** — not that it does so reliably. The design spec
explicitly defers "any per-model pass-rate guarantee," so this is a recorded
measurement, not a missed bar.

Note also that 1 of the 9 is a *stopping* failure, not content: the harvest gate
requires `stopReason == .eos`, so a turn that runs to the token wall is never
harvested even though the repeated-heading abort could recover its first pass.
Widening that gate is a separate decision (see limitations).

The build arm's earlier "1 success in 4" did not survive re-reading the primary
evidence. Of the **three** failures (4 runs, 1 success), **two** — captures
`171016` and `171258` — contained complete, EOS-terminated FastAPI apps under
every `#path` heading, differing from the success only in the absence of
` ``` ` lines. The number was measuring the parser, not the model.

The third failure, `171057`, is **not** in that category and an earlier draft of
this record overstated it: it stopped at `limit` (the 8192-token wall), not
`eos`, and its first pass covers 4 of the 6 granted files. It is recoverable —
the repeated-heading abort keeps that first pass rather than yielding an empty
tree — but it was a genuine stopping failure, not a fence-only failure.

Fixtures of the raw output are committed at `fixtures/agenttest/harvest/` and
replayed by `HarvestCaptureReplayTests` under the **real 6-file grant** read from
the captures' own `packet.json` (an approximated 5-file grant in an earlier draft
made the replay assert an out-of-grant heading the live runs never produced).

**Attribution.** The first verification run after the fix emitted **zero fences
across all three phases** and still reached 13/13. Under the old parser it would
have died at phase 1, so the pass is attributable to the change rather than to a
lucky draw.

**Seams that did not fire.** Across those 5 runs the two-turn emission seam and
the repeated-heading abort fired **0 times** on the build arm. The lenient
harvest alone carried them. Both remain unexercised live on this arm — pinned by
unit tests and by capture replay, but not by a live build run.

## Corrections folded in

Three confident-looking findings dissolved under scrutiny during this phase. All
three dissolved the same way: by going back to primary evidence instead of
trusting a recorded summary.

1. **"Seed nondeterminism."** `AgentCommand.swift:89` omits `--seed` entirely
   when seed is 0, so the runs were never seeded. Recording a bare `"seed": "0"`
   made ordinary sampling variance look like an unexplained finding.
2. **"Sampler discrepancy."** No temperature is ever transmitted; the engine
   samples at its own family defaults. `SamplingPolicy.temperature` defaulting to
   0 meant every stored packet claimed greedy decoding for non-greedy runs.
3. **"Build arm 1/4."** A parser artifact, as above.

A fourth instance of the same class was found and fixed in `05a4fcc`: a failing
validation recorded `digest: "sha256:e3b0c442…"` — the hash of the empty string —
because only stdout was hashed and the traceback goes to stderr.

**Standing lesson.** A record must never assert something the run did not
produce. Every packet and receipt field should be either *transmitted* or
*derived*, never a bare value with ambiguous provenance.

## Done-when audit

All seven criteria from the design spec's Verification section are met:

1. Step-0 forcing gate — recorded 0→N measurement (nudge ablation, 0 tool calls).
2. `LabeledBlockParser` fail-closed unit tests pass; text-only outcome plus
   injected paths produces `.candidate`; out-of-grant paths still refused;
   `ThinkHarvest` and its tests are gone (verified absent from the tree).
3. `HandoffPacket.textContract` decodes with and without the field
   (`HandoffPacketTests`).
4. Repair experiment — host-verified, 4/4 at 13/13, `fileCap` precondition
   enforced.
5. `runOnce` harvest hook (fake tier) turns labeled-block output into a graded
   candidate; 0 blocks emits `.contractNotFollowed` and stops the transaction.
6. Build experiment — host-verified candidates: imports clean, required file set
   covered, and **failures bucketed *content*, not harvest/parse/write**. This is
   the criterion the pre-fix build arm failed and now meets.
7. Full suite green (494, integration suite green); every text-contract capture
   carries the `resultClass` label.

Note that the design spec explicitly **defers** "any per-model pass-rate
guarantee." 3-of-5 is therefore not a shortfall against the bar; the bar asks for
a host-verified candidate with content-bucketed failures, which is what the
evidence shows.

## Known limitations — carried forward, not fixed here

1. **No phase-level repair.** A phase that fails its import check aborts the run
   at `main.swift` before `commitBack()`, so the repair loop — which *is* wired
   after acceptance failure, on worker 2 — is never reachable. This is what
   stopped both failing build runs. The abort is deliberate (finding C17: it
   stops a broken tree chaining into the next phase), so removing it without
   adding repair would regress C17.
2. **`RepairLoop` exits immediately on any receipt**, including
   `validationFailed`. The rationale holds — the receipt path discards the
   worktree and never advances `head`/`lastGrade`, so a retry would replay a
   byte-identical dispatch — but it means a repair that breaks an import gets no
   second attempt even though the traceback is new evidence.
3. **The lenient harvest cannot distinguish prose from file content** under an
   allowlisted heading, because without a fence there is no delimiter. The fenced
   form remains what the directive asks for; leniency is a fallback and is
   deliberately not advertised to the model. Three consequences, in increasing
   order of how much they should worry us:
   - *Trailing junk glues onto the last file.* Already visible in `unfenced-b`,
     where the `#uvicorn.run(...)` and `#uv run --project …` lines after
     `tests/test_app.py` are appended into its body. Harmless only because `#`
     is a Python comment; in an `.html` grant the same text would render, and
     the import check never loads templates.
   - *A repair turn could overwrite a working file with prose.* If the model
     emits `#app.py` and then narrates, the host writes the narration. The
     observed repair failure mode is prose with **no** heading, which harvests
     nothing and correctly triggers the emission follow-up — so this is a
     structural risk, not an observed one. But the repair arm re-emits complete
     files over known-good ones, so the blast radius there is a destroyed file
     rather than a bad candidate.
   - *The failure taxonomy blurs.* This is the one that most affects what this
     phase can claim. Turns previously classified `contractNotFollowed` can now
     land as `validationFailed` or as acceptance failures, so the harness can no
     longer cleanly separate "the model ignored the contract" from "the model
     wrote buggy code." The 0-`contractNotFollowed` result should be read as
     *the harvest stopped rejecting well-formed work*, not as *the model became
     perfectly compliant*.
4. **The repeated-heading abort can drop a file** that first appears after the
   first repeat. Not observed in any of the four captures (checked: zero unique
   files lost in all four), but structurally possible.
5. **No generation-time stopping control.** The engine's pool protocol has no
   cancel, so a degenerate run still pays to the token wall; the abort is
   harvest-time only.

## Result class

Every run in this record: **drafting quality + host orchestration, not agency.**
