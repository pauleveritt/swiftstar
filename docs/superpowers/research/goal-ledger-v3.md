# Goal ledger v3 — P16 stage 2 (apparatus trustworthiness)

> **Goal: an apparatus that can attribute a failure.** Done when ONE batch of
> ≥8 Mellum cells satisfies all four:
>
> **(a)** zero cells fail in a way no invariant covers;
> **(b)** every invariant is auditable — V4 included;
> **(c)** two runs at the same seed produce byte-identical dispatched packets;
> **(d)** every check has fired on a known-bad drawn from *that* batch, not
> only a frozen fixture.

**P16's done-when is unchanged** — ≥10 valid Mellum cells spanning ≥2 seeds and
both path styles. This is a prerequisite stage, not a replacement. The cell
count resumes when this goal is met.

Driven by [`.claude/commands/goal.md`](../../../.claude/commands/goal.md) v3
via `/loop /goal`. Predecessor: [`goal-ledger.md`](goal-ledger.md) (v1+v2, 13
entries — **read entries 7, 12 and 13 before touching the auditor**). Full
context: [`2026-08-26-overnight-80-cell-verdict.md`](2026-08-26-overnight-80-cell-verdict.md).

## Invariants (frozen for this goal)

- **V1** — a `.validationFailed` round's write must survive into the next round.
  *The check must establish the round WROTE the missing file, not merely ran.*
- **V2** — no dispatched packet's evidence may be a bare pytest collection error
- **V3** — no directive asserting "exactly one file is wrong" while ≥2 writable
  files are missing in the same packet
- **V4** — every `verdict.json` reason must trace to text some packet dispatched
- **V5** — every packet must have been deliverable
- **V6** — no file content may originate in an emission containing zero fences
- **V7** — two runs at the same seed must dispatch byte-identical packets

---

## Carry-forward state (not an iteration)

Written when v3 opened, so iteration 1 starts from evidence rather than memory.
Every line below is sourced from v2's ledger or from a command re-run at
`070e0f4`.

### What is landed and live-confirmed

| | fix | confirmed by |
|---|---|---|
| **V1** | `head` advances via `commitForRepair` on `.validationFailed` | fixture 13/13 |
| **V2** | precondition manifest replaces collection aborts | live: 0 of 6 acceptance packets in the n=4 batch carried a collection error; one named `models.complaints` as the single unmet gate of 9 |
| **V3** | directive branches on missing-file count | live: Mellum emitted 5 distinct files |
| **V5** (`exceeds context` clause only) | `cappedFailureOutput` kept `byteCount - cap`, now keeps `cap` | live: a round-2 packet kept **8194 bytes for cap 8192**, and what it kept was the pytest summary naming all 13 failing tests |
| exhaustion | `.exhausted` carries `BestReached`; verdict grades the furthest tree | live: `code.md` showed 2 files |
| budget | `AGENTTEST_REPAIR_ROUNDS`, default 2, in `run-config.json` | live: `repairMaxRounds = 5` |

### Open defects, in the order they should be fixed

1. **V7 — non-reproducibility.** Repair packets embed the per-round temp
   worktree UUID inside tracebacks. Same seed + same config ⇒ different prompt.
   Proven: round-2 packets of `20260826-104811` and `20260826-112536` (both
   mellum/absolute/seed1) diverge from the traceback line onward, and the first
   **repaired** where the second **failed**. Fix first: it is small, it is the
   precondition for every controlled comparison after it, and it restores
   prompt-prefix caching.
2. **V6 — prose harvested into source files.** `LabeledBlockParser.parse`'s
   lenient path takes an unfenced heading's body as file content. Mellum emitted
   six headings, prose under each, zero fences, ending *"Now I'll create all the
   missing files with the appropriate content:"* — and the harness wrote that
   plan into six real files. Compiling the `.py` contents the packets show as
   current: **3 of 8 cells** across both n=4 batches carried non-compiling
   `app.py`, `models.py` and `tests/test_app.py`. Ruling in the v3 contract.
3. **V1 check false positive.** Gates on the round having *run*, never on it
   having *written*. `20260826-112121` rounds 3–5 emitted byte-identical
   `app.py` and never once emitted the missing `tests/test_app.py`, so the
   unchanged missing set was correct behaviour. Any V1 count from the old check
   on a multi-round capture is void.
4. **V4 unauditable.** `main.swift:716` captures only `phases[0]`. Required by
   done-when (b).
5. **V5 `limit` clause — escalated, undecided.** A cell died on a runaway
   8192-token generation with `ctx_used=11982` of 32768. Whether that is a
   harness bound or a model property is measurement semantics. **Do not decide
   this inside the loop.**

### Standing hazards

- **An intermittent integration-tier failure that hides its own identity.**
  Twice now `swift test` reported `failed with 1 issue` naming no test, then
  passed 4 consecutive re-runs. Not reproduced on demand; not dismissible.
- **A larger round budget may compound damage,** since rounds are cumulative
  since the V1 fix. Untestable until V7 holds.

### Cells

**Valid Mellum cells carried forward: 4** — `20260826-065840` plus three from
the n=4 batch (`104811`, `105213`, `105529`). **Model result among them: 0/3
passes** (the fourth predates the batch). The four cells of the budget=5 rerun
are **not** counted: all died in phase-1 repair, none reached acceptance, and
one carried the V6 defect.

These counts are inherited under v2's invariant set. **They must be re-audited
under V6 and V7 before they are claimed against this goal** — that re-audit is
iteration 1.

**done-when: a=no b=no c=no d=no**

---

## 1 — 2026-08-26 — audit — **ESCALATION**

**did:** Implemented `check_v6` with fixtures and re-audited all nine captures
under the v3 invariant set. V6 works and fires — **and in the course of proving
it, found a defect it does not cover that invalidates one of the four
carried-forward "valid" cells.**

**cells:** valid=6 blocked={V5:1, V6:2, V1:1} unauditable={V4:9} of 9
*(104551 is blocked by both V5 and V6, so the blocked-cell count is 3.)*

**done-when: a=no b=no c=no d=no**

**model:** (omitted — audit iteration.)

**evidence:**

```
$ python3 Tools/audit-goal-invariants.py --self-test
  [ok] V6 20260826-112536-roadmap/-: expected fail, got fail
       (known-bad: round-1 emission had 6 headings, prose under each, zero fences)
  [ok] V6 20260826-105529-roadmap/-: expected pass, got pass
       (known-good: every harvested file came from a fenced block)
self-test: PASS

per-cell re-audit (9 cells):
  065840 VALID    104551 BLOCKED(V5 limit, V6)   104811 VALID
  105213 VALID    105529 VALID                   112121 BLOCKED(V1)
  112536 BLOCKED(V6)   112907 VALID              113440 VALID
```

`check_v6` matches a packet's shown file body verbatim against the text of a
zero-fence turn, so the link from harvested content back to the emission it
came from is evidence, not inference.

---

### The claim I was about to make and did not **[v3 rule]**

I was about to record "V6 now covers the prose-harvest defect" and carry
`20260826-104811` forward as valid. A cross-check against the compile-based
scan from v2 entry 13 disagreed: that scan flagged 104811's `app.py`,
`models.py` and `tests/test_app.py` as non-compiling, but V6 passed the cell.
**V6 was not wrong — it was too narrow, and the disagreement is the finding.**

### Escalation — a defect no invariant covers, and the standing ruling does not fix it

104811 has **no zero-fence turns at all**; the emission that poisoned it
contains **12 fences**. The shape is:

```
# app.py

The failure output shows `ModuleNotFoundError: No module named 'app'`. ...
Based on the mission description, ... Let me create a basic `app.py` file:

```python
from fastapi import FastAPI
...
```
```

`LabeledBlockParser.parse` allows one optional blank line between a heading and
its fence. Here the blank line is followed by *prose*, so the heading falls to
the lenient path, whose body loop `break`s at the first fence. The prose is
harvested as the file's contents; control then returns to the outer loop, which
sees a fence with no accepted heading and **skips it to its close**. The
model's real code is discarded and its commentary is written to disk in place
of it.

Measured across all nine cells — headings that took the lenient path, and how
many of those had actual fenced code discarded after them:

```
20260826-104551  lenient= 7   CODE DISCARDED= 1
20260826-104811  lenient= 6   CODE DISCARDED= 6      <- every one
20260826-112536  lenient=30   CODE DISCARDED= 0      <- the zero-fence plan; no code to lose
  (all other six cells: 0 and 0)
```

**Consequences, stated plainly:**

1. **`20260826-104811` is not attributable to the model and must not be counted
   valid.** Mellum emitted correct-looking fenced code six times and the harness
   kept its prose instead. It is one of the three cells behind v2's headline
   `model: 0/3`, so that number is now suspect and should not be quoted.
2. **The standing harvest ruling does not fix this case.** The ruling gates
   lenience on the emission containing ≥1 fence *anywhere*; this emission has
   twelve. The zero-fence rule is correct and worth keeping — it fixes 112536 —
   but it is a strict subset of the defect.
3. This is both a cell failing in a way no invariant covers (**done-when (a)**)
   and a change to what the model is shown, which the v3 contract assigns to
   the human as measurement semantics. **The loop does not decide it.**

For the record, the narrower rule that would cover this case — *a heading
followed by anything other than a fence, when a fence appears before the next
allowlisted heading, means the fence is the content and the prose is not* — is
a candidate, not a decision.

**next:** **STOP — escalate.** V6's implementation stands and is proven; the
invariant it encodes is too narrow to reach done-when (a). Needs a ruling
before any further fix or GPU work.

## 2 — 2026-08-26 — fix (V6) — **ESCALATION**

**did:** Adopted the human's candidate rule — *prose between a heading and its
fence does not beat the fence* — red-then-green in `LabeledBlockParser`, and
widened `check_v6` to audit it. **Did NOT implement the earlier zero-fence
ruling: three frozen fixtures refute it.**

**cells:** valid=5 blocked={V6:3, V5:1, V1:1} unauditable={V4:9} of 9
*(104551 is blocked by both V5 and V6; four distinct cells are blocked.)*
`20260826-104811` moves from VALID to BLOCKED, as iteration 1 predicted.

**done-when: a=no b=no c=no d=no**

**model:** (omitted — fix iteration.)

**evidence:** red-then-green, both halves pinned separately:

```
# before
✘ proseBetweenHeadingAndFenceDoesNotBeatTheFence
  ↳ expected the fenced code, got: The failure output shows a ModuleNotFoundError. Let me create the file:
✘ aFenceAfterTheNextHeadingDoesNotBackfillThePreviousOne
  ↳ (models?.content → "commentary") == "MODELS = 1"

# after
✔ LabeledBlockParserTests   — 24 tests passed
✔ HarvestCaptureReplayTests —  4 tests passed   (all three zero-fence captures still harvest)
$ swift test                          # 545 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test  # 545 tests, 74 suites — passed
$ python3 Tools/audit-goal-invariants.py --self-test   # PASS
```

Re-audit under the widened check:

```
065840 VALID   104551 BLOCKED(V5 limit, V6 x1)   104811 BLOCKED(V6 x6)
105213 VALID   105529 VALID                      112121 BLOCKED(V1, known false positive)
112536 BLOCKED(V6 zero-fence)   112907 VALID     113440 VALID
```

`check_v6` gained a fixture for the widened clause — `104811`, the cell the
zero-fence detector alone passed. That is done-when (d) working as intended: a
check that only ever fired on the defect it was written for would have shipped
believing itself complete.

---

### The claim I was about to make and did not **[v3 rule]**

I was about to implement both halves of the standing harvest ruling. Checking
the existing tests first showed the fence-count of every frozen harvest fixture:

```
fixtures/agenttest/harvest/fenced.txt       fences=20
fixtures/agenttest/harvest/repeated.txt     fences=0
fixtures/agenttest/harvest/unfenced-a.txt   fences=0
fixtures/agenttest/harvest/unfenced-b.txt   fences=0
```

`unfenced-a.txt` begins `#app.py` followed immediately by
`from fastapi import FastAPI, Request` — **real code, zero fences.** These are
P15's captures, and they are correct harvests.

### Escalation — the zero-fence ruling is refuted by evidence that predates it

**"An emission with zero fences is a plan, not code" is false.** Three of the
four frozen fixtures are zero-fence emissions carrying real code, and
implementing the ruling would break `unfencedCaptureAHarvestsEveryFile`,
`unfencedCaptureBHarvestsEveryFileWithCommentsIntact` and
`repeatedCaptureHarvestsTheFirstDraftAndFlagsRepetition`. I did not implement
it. The candidate rule is independent of it and is implemented.

**This also means V6's frozen text is wrong in the same way.** V6 reads "no
file content may originate in an emission containing zero fenced blocks."
Against a P15-shaped emission that clause marks a *correct* harvest invalid.
It happens not to misfire on the nine cells audited here — `112536`'s
zero-fence bodies really are prose — but the check cannot tell prose from code,
so it is a false positive waiting for the first P15-shaped Mellum cell.

The real distinguisher between `unfenced-a` (good) and `112536` (bad) is
whether the body is code or commentary — and filtering harvested bodies by
whether they parse is the option the human explicitly rejected, for a reason
that still holds: it would suppress the broken code we are trying to measure.
Note the two are not the same thing — *commentary* and *broken code* are
different categories — but separating them programmatically is close to a parse
attempt, which is why this is not the loop's call.

**Options, offered as candidates and not decided:** withdraw V6's zero-fence
clause and keep only the discarded-fence clause; or keep it and accept known
false positives on P15-shaped emissions; or distinguish commentary from code by
some means the loop is not authorised to choose.

**next:** **STOP — escalate.** The discarded-fence half is landed and proven.
The zero-fence half needs a ruling before V6 can be trusted, and V6 is required
by done-when (a) and (b). The V1 check false positive (`112121`) is the
obvious next fix once V6's text is settled.

## 3 — 2026-08-26 — audit (correction) — retracts V6's zero-fence clause

**did:** On the human's ruling, withdrew V6's zero-fence clause from both the
contract and `check_v6`, and re-audited. **Every V6 count that clause produced
is void** — it is retracted, not merely disabled.

**cells:** valid=6 blocked={V6:2, V5:1, V1:1} unauditable={V4:9} of 9
*(104551 is blocked by both V5 and V6; three distinct cells are blocked.)*

**done-when: a=no b=no c=no d=no**

**evidence:**

```
$ python3 Tools/audit-goal-invariants.py --self-test
  [ok] V6 20260826-104811-roadmap/-: expected fail, got fail  (widened clause)
  [ok] V6 20260826-105529-roadmap/-: expected pass, got pass
self-test: PASS

065840 VALID   104551 BLOCKED(V5 limit, V6 x1)   104811 BLOCKED(V6 x6)
105213 VALID   105529 VALID                      112121 BLOCKED(V1)
112536 VALID   112907 VALID                      113440 VALID
```

**What moved and why:** `20260826-112536` goes BLOCKED → VALID. It is the
zero-fence "plan" cell — six headings, prose under each, no code. Under the
amended ruling the harness did what lenient harvest is for; the model failed
the contract. That is a model failure and the cell is attributable.

**The thing that is now true and uncomfortable, recorded rather than fixed:**
that run is recorded as `validationFailed`, not `contractNotFollowed`, so the
capture mislabels *how* the model failed. The cell counts as valid and the
label is wrong. Reclassifying it is measurement semantics and is not the
loop's call; it is written into standing ruling 1 so it cannot be forgotten.

The retired fixture (`112536` as a V6 known-bad) was removed rather than
re-pointed, so no check claims a known-bad it no longer detects.

**next:** **fix** — `check_v1`'s false positive on `112121`, the only remaining
block whose cause is a known-broken check rather than a real defect. V1's
frozen text already carries the correction it needs.

## 4 — 2026-08-26 — fix (V1 check) — corrects a check, voiding its old counts

**did:** Gated `check_v1` on the round having **written**, not merely run —
the correction V1's frozen text has demanded since v2 entry 13. **Every V1
result the old check produced on a multi-round capture is void.**

**cells:** valid=7 blocked={V6:2, V5:1} unauditable={V4:9} of 9
*(104551 is blocked by both V5 and V6; two distinct cells are blocked.)*

**done-when: a=no b=no c=no d=no**

**evidence:**

```
$ python3 Tools/audit-goal-invariants.py --self-test
  [ok] V1 20260826-050316/repair-phase1: expected fail, got fail   (known-bad, unchanged)
  [ok] V1 20260826-085813/repair-phase1: expected pass, got pass
  [ok] V1 20260826-112121/repair-phase1: expected pass, got pass   (current-batch known-good)
self-test: PASS

065840 VALID   104551 BLOCKED(V5 limit, V6 x1)   104811 BLOCKED(V6 x6)
105213 VALID   105529 VALID                      112121 VALID
112536 VALID   112907 VALID                      113440 VALID
```

**The check did not get weaker.** Its known-bad still fails, and now says more:

```
round 1 ended validationFailed but round 2 was dispatched the identical missing
set ['app.py','models.py','templates/...','tests/test_app.py'], and the model
did emit ['app.py','models.py'] -- the write did not survive
```

Naming the files the model emitted that failed to survive is the evidence the
old wording asserted without having.

**How it establishes "wrote":** allowlisted paths emitted as heading lines
across the cell's turns. Round records carry a receipt and a grade but no
mutation list, and the packets' file contents are the very thing V1 compares —
so the emission is the only independent evidence available. Stated limitation:
headings are collected per-cell, not per-round, so the gate is conservative —
it can only ever suppress a FAIL, never manufacture one.

**Why v2 never caught this:** the frozen V1 fixture is a 2-round capture, and
the false positive needs 3+. `112121` is now a fixture precisely because it
comes from the current batch — done-when (d) is the rule that produced this fix.

**next:** **fix** — V7 (reproducibility). It is the carry-forward's first
priority, needs no GPU, and until it holds no comparison between two runs is
controlled — including the round-budget question v2 could not answer.

## 5 — 2026-08-26 — fix (V7, partial) — **ESCALATION, and retracts a v2 diagnosis**

**did:** Landed worktree-path normalisation in repair evidence (red-then-green)
and then measured whether it achieves V7. **It does not, and finding out why
retracts v2 entry 13's root-cause claim.**

**cells:** valid=7 blocked={V6:2, V5:1} unauditable={V4:9} of 9 — unchanged;
this iteration changes the apparatus, not the classification.

**done-when: a=no b=no c=no d=no**

**evidence:**

```
# before
✘ worktreePathsAreNormalisedOutOfEvidence — no member 'normalizingWorktreePaths'
# after
✔ MachineEvidenceTests — 12 tests passed
$ swift test                          # 546 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test  # 546 tests, 74 suites — passed
```

Measured on real packets, not asserted:

```
112121 packet 4 vs 5 (consecutive rounds, same run)
   diff lines before=  5   after normalisation=  0   identical=True
104811 vs 112536 round 1 (mellum/absolute/seed1, two runs)
   diff lines before=  0   after normalisation=  0   identical=True
```

Implemented Foundation-free (this type is deliberately pure) and matched on the
UUID shape rather than one known URL — round 1's grade comes from the *failed
phase's* worktree, not the round's own, so normalising against a single URL
would have missed it.

**What it did buy:** consecutive rounds inside a run no longer churn the packet
(5 differing lines → 0), which restores prompt-prefix caching across rounds.
That is real and worth keeping.

---

### Retraction — v2 entry 13's V7 root cause was wrong

Entry 13 concluded: *"a fixed seed does not make a run reproducible … same seed,
same config, different invocation ⇒ different prompt ⇒ different sampling."*
**The second link in that chain is false.** The round-1 packets of `104811` and
`112536` were **already byte-identical before any normalisation** — the prompt
was never the variable. I reached the wrong conclusion by diffing *round-2*
packets, where model output had already diverged, and reading the traceback
line at the top of that diff as the cause rather than a symptom.

Where the divergence actually starts:

```
turn 0:  SAME    (0 chars, engine handshake)
turn 1:  DIFFER  (2660 vs 3027 chars)   <- the FIRST model emission
turn 2:  DIFFER  (7117 vs 1448 chars)
```

Turn 1 is the phase-1 implement turn. It precedes every repair packet. And its
inputs are identical:

```
packet.json taskText sha  45a6cb026cda  (3897 bytes)   — both runs
seed = 1                                                — both runs
sampler = temp 0.6 top-k 20 top-p 0.95 min-p 0.0        — both runs
```

**Identical prompt, identical recorded seed, identical sampler, different
output on the first turn.** The harness forwards `--seed` whenever seed > 0
(`AgentCommand.swift:99`), and the capture records seed=1, so the seed is set as
far as the harness can express it. The remaining candidates are engine-level:
the seed not reaching the sampler, or non-deterministic GPU kernels. `wire.trace`
does not record argv, so the captures cannot settle it.

### Escalation

**V7 is not reachable by harness changes alone**, and the obvious remedies are
measurement semantics, not implementation:

- Greedy decoding (temp 0) would very likely make runs reproducible — and would
  change what the model does, so every prior number would describe a different
  sampling regime.
- Accepting non-determinism means V7 must be restated as a tolerance
  ("same seed ⇒ same *distribution*"), which changes what a valid cell means
  and what a comparison between two batches can claim.

Either way the loop does not decide it. **The cheap next measurement, if
wanted: dispatch one identical prompt twice at a fixed seed and diff the two
emissions** — ~2 minutes of GPU, and it separates "seed not wired into the
engine" from "kernels are non-deterministic" without touching the pipeline.

**next:** **STOP — escalate.** V7 needs a ruling. If the answer is the
determinism probe, that is a confirm-tier run and the loop can execute it once
told which way to resolve the outcome.

## 6 — 2026-08-26 — probe (determinism) — **ESCALATION**

**did:** Dispatched one identical fixture prompt three times at seed 1 and
diffed the emissions. **The seed reaches the engine and the runs still differ.**
Found a third packet-instability source in the process. No model numbers are
recorded — this is a probe.

**cells:** unchanged (valid=7 blocked={V6:2, V5:1} unauditable={V4:9} of 9);
the three fixture captures are not pipeline cells and count toward nothing.

**done-when: a=no b=no c=no d=no**

**evidence:**

```
runs A/B, --fixture misleading-locus --variant mellum-2.1, AGENTTEST_SEED=1
  prompt sha A: 4a6452bbeaa4   prompt sha B: 4a6452bbeaa4   identical=True
  turn 0: SAME    (engine handshake)
  turn 1: DIFFER  (1784 vs 2223 chars)   worker=1 both, generated 473 vs 586
  turn 2: SAME    (935 chars, identical hash, generated 271 both)
```

**The seed IS forwarded.** Engine argv captured live from `ps -ww` during a run:

```
ds4-agent -m .../mellum-thinking-TARGET.gguf -c 32768 --metal --non-interactive
  --json-events --workspace ... --shell off --host-tools -n 8192 --nothink
  --seed 1 --subagent-pool 3
```

and `ds4-agent --help sampling` documents `--seed N — Sampling seed for
reproducible non-greedy runs`.

**It is not worker assignment.** Both runs were served by `worker=1`, and both
prefilled identically: `4596 − 473 = 4123` and `4709 − 586 = 4123` tokens.
Identical prefill, identical seed, same worker, different sampled output.

**Turn 2 being byte-identical does not discriminate** between the remaining
causes, and I nearly wrote that it did. A peaked continuation produces the same
tokens whether the seed works or is ignored entirely, so it is evidence that
determinism is *achievable on low-entropy turns*, nothing more.

### Eliminated, and what is left

| candidate | verdict |
|---|---|
| seed not forwarded to the engine | **eliminated** — argv shows `--seed 1` |
| pool worker assignment varies | **eliminated** — `worker=1` in both runs |
| prompt differed | **eliminated** — identical sha, identical prefill length |
| engine ignores/mishandles the seed | **open** |
| non-deterministic Metal kernels perturb logits | **open** |

Separating the last two needs a greedy (`--temp 0`) run. The harness never
transmits a temperature — `engineTemperature` is read from the variant and the
engine samples at its own family defaults (`temp 0.6 top-k 20 top-p 0.95`) —
so that needs a code change AND it changes what the model does. That is the
escalated V7 decision, not a probe step.

### A third instability source, found by accident

The third run's packet sha differed from A and B. The whole diff:

```
-1 failed, 12 passed, 3 warnings in 0.20s
+1 failed, 12 passed, 3 warnings in 0.16s
```

**pytest's wall-clock duration is embedded in the failure evidence.** A and B
matched only because both happened to run in 0.20s. So V7 has at least three
sources, of which one is now fixed:

1. worktree UUID paths — **fixed** (iteration 5)
2. pytest timing lines — **open**, and fixable in the harness, same class as (1)
3. engine sampling non-determinism — **not fixable in the harness**

Source 2 matters beyond V7: a timing that changes every run also breaks
prompt-prefix caching for everything after it in the packet.

**next:** **fix** — normalise pytest timings out of the evidence (source 2).
It is in the same authorised class as the worktree-path fix under standing
ruling 3, needs no GPU, and is worth landing whichever way V7 is ruled. Source
3 still needs the human's ruling and no amount of harness work removes it.
