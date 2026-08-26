# Goal ledger — P16 (repair harness validity)

> **Goal: ≥10 valid Mellum cells** — pipeline runs whose outcome is
> attributable to the model under every validity invariant below — spanning
> ≥2 seeds and both path styles, with the model's pass/fail recorded either
> way. The goal is a count of valid measurements, not passes: a clean run
> where Mellum fails everything is progress; a "pass" that violates an
> invariant is zero progress.

Full context: [`2026-08-26-overnight-80-cell-verdict.md`](2026-08-26-overnight-80-cell-verdict.md).
Driven by [`.claude/commands/goal.md`](../../../.claude/commands/goal.md) via
`/loop /goal`. Frozen validity invariants (do not widen/narrow mid-goal):

- **V1** — a `.validationFailed` round's write must survive into the next round
- **V2** — no round's evidence may be a bare pytest collection error
- **V3** — the repair directive must not assert "exactly one file is wrong"
  while ≥2 writable files are missing/failing in the same packet
- **V4** — every `verdict.json` reason must trace to text some packet actually
  dispatched
- **V5** — every packet must have been deliverable (no context overflow, no
  `turnDidNotEnd`, no `limit`/`contextFull` stop)

---

## 1 — 2026-08-26 — audit

**did:** Classified all 80 existing 2026-08-25→26 captures against V1–V5,
mechanically (grep/JSON checks over the captures, not judgment from the
verdict record's prose).

**cells:** Mellum: valid=**1** blocked={V1:19, V2:20, V3:39, V5:1} of 40.
Laguna (context, not the goal): valid=38 blocked={V3:1, V5:1} of 40.

**model:** 0/1 among Mellum's valid cells (NOT the goal) — the one valid cell
(`20260826-065840`, abs/on seed 9) died on `turnDidNotEnd` in phase 2, which
V5 does not catch because that death has no `stop_reason` line at all (it's
an uncovered failure mode noted in the verdict record's Defect 4, not yet a
frozen invariant — flagging, not adding a V6 mid-goal).

**evidence:**

```
$ python3 audit_v1_5.py
=== laguna: 38 valid / 40 total ===
    blocked breakdown: {'V3': 1, 'V5': 1}
    valid cells span seeds=[1..10] path_styles=['absolute', 'relative']
=== mellum: 1 valid / 40 total ===
    blocked breakdown: {'V1': 19, 'V3': 39, 'V2': 20, 'V5': 1}
    valid cells span seeds=[9] path_styles=['absolute']
```

V1's check required a correction mid-iteration: the first implementation
compared packet[k] vs packet[k+1] directly (both are pre-turn snapshots, so
they're never different — packet generation happens *before* each round's
turn runs). Verified the bug by hand against `20260826-050316`'s known-bad
round 1→2 pair before trusting the script, then gated the comparison on round
k's *receipt* actually being `.validationFailed` (proof a turn fired) before
comparing missing-sets — 19 cells match the "≥1 validationFailed round"
count independently established in the verdict record.

**New, not in the prior verdict record:** V3 fires on **39/40** Mellum cells
— more than V1 (19) or V2 (20) — because the directive's self-contradiction
is present from round 1 in nearly every cell (build wrote nothing, so 6 of 6
writable files are already missing the moment repair starts). V3 also fires
on **1 Laguna cell** (`20260826-015344`, phase-1 repair with 2 files
missing) — the directive defect is not Mellum-specific, it just never gates
Laguna's outcome because Laguna's single round usually resolves it anyway.

**next:** **fix** — V3 blocks the most cells (39) and, per the verdict
record's serial-not-parallel warning, fixing V1 alone would just reroute
those 19 cells into V2/V3 territory, not out of it. Land recommendation 2
(make `repairPacket`'s directive conditional on missing-file count) with a
red-then-green test, matching ROADMAP's P16 fix ordering (#2 before #1 is a
deliberate deviation from the doc's ranking — #2 is the cheapest to fix and
unblocks the audit's dominant blocker; #1 is still required next since V3
alone won't fix V1's 19 cells).

## 2 — 2026-08-26 — fix (V3)

**did:** Landed recommendation 2 — `RepairContext` now carries
`missingWritableFiles: [String]`, computed by `RepairLoop.run` directly
against the repo's object store (`git cat-file -e <head>:<path>`, no worktree
needed) *before* `packetBuilder` runs each round, since packet evidence is
otherwise only known after the worktree exists. `repairPacket` in
`main.swift` now branches on `ctx.missingWritableFiles.count`: ≥2 emits a
new "N files are missing or wrong — not one … emit each that needs to
change" directive and drops "do not add new files"; ≤1 keeps the original
"exactly one file is wrong" text verbatim. `writableFiles: []` defaults kept
every other `RepairLoop.run` call site and test compiling unchanged — only
the 3 real call sites (fixture, phase-scoped, acceptance) and `PhaseRepair`
(which already had `packet.writableFiles` in scope) needed a one-line addition.

**cells:** unchanged this iteration (0 new captures) — carried forward:
Mellum valid=1 blocked={V1:19, V2:20, V3:39, V5:1} of 40.

**model:** n/a — no new model output this iteration.

**evidence:**

```
$ SWIFTSTAR_INTEGRATION=1 swift test --filter repairContextCarriesMissingWritableFilesAtHead
✔ Test repairContextCarriesMissingWritableFilesAtHead() passed after 0.252 seconds.
```
(Red first: the same test failed to compile — "extra argument 'writableFiles'
in call" / "value of type 'RepairContext' has no member 'missingWritableFiles'"
— against the pre-fix API, confirming the test exercises the new seam.)

```
$ swift test                      # 537 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test   # 537 tests, 74 suites — passed
```

**next:** **confirm** — verify the fix doesn't regress the untouched
single-file branch live, at fixture tier, before touching V1 or spending
pipeline time.

## 3 — 2026-08-26 — confirm

**did:** Ran one live fixture-tier repair (`plausible-wrong-fix`, mellum,
seed 1) to confirm the V3 refactor didn't change behavior on the branch it
left alone (`missingWritableFiles.count <= 1`, the well-calibrated case).
Checked the engine lock informally first (`ps aux` for
`llama|agenttest|caffeinate` — empty, confirmed idle) since there is no
formal cross-process lockfile in this codebase, only the practical rule of
not running two model loads at once.

**cells:** n/a (fixture tier, not counted toward the Mellum-pipeline goal).

**model:** 1/1 — `20260826-085251-fixture-plausible-wrong-fix`: baseline
exit=1, repaired, **13/13 exit=0**.

**evidence:**

```
$ DS4_DIR=.../external/ds4 SWIFTSTAR_MODEL=.../mellum-thinking-TARGET.gguf \
  AGENTTEST_SEED=1 swift run swiftstar-agenttest --fixture plausible-wrong-fix
[agenttest] fixture plausible-wrong-fix: baseline exit=1
[agenttest] fixture plausible-wrong-fix: repaired — exit=0
[agenttest] fixture plausible-wrong-fix: 13/13 ✓
```

Dispatched packet text checked directly against the capture — byte-identical
to the pre-fix directive:

```
$ python3 -c "import json; t=json.load(open('captures/agenttest/20260826-085251-fixture-plausible-wrong-fix/repair-packet-1.json'))['taskText']; print('Exactly one file is wrong' in t)"
True
```

**next:** **measure** — the latest audit (entry 1) already shows the harness
is nowhere near zero-blocked, so per the action-priority order this is not
yet a "measure" in the strict sense (audit still shows harness-blocked
cells among *existing* captures) — but V3 is now fixed in code and this
confirm run is clean, so the next iteration should dispatch a small *fresh*
Mellum pipeline batch (≤5 cells) specifically to see whether V3's fix
changes the shape of failures (does round 1 now write more than one file
when build wrote nothing?), then audit those new captures before writing
any pass/fail number down. V1 (the discard defect) is not yet fixed, so
these cells are expected to still fail — the goal is to observe whether V3's
fix changes *what* gets built, not to expect a pass yet.

## 4 — 2026-08-26 — fix (V1)

**did:** Landed recommendation 1 — the `.validationFailed` path in
`RepairLoop.run` now advances `head` via
`WorktreeDispatcher.commitForRepair(wt, packet:in:)` before `continue`ing,
so round N's write survives into round N+1's worktree. `finalize` only
commits on the `.candidate` path, so previously the receipt path left `head`
at the same base and the `defer` tore the worktree down — making "N rounds"
N independent single-shot attempts. `commitForRepair` already existed for
exactly this shape (P12.8 uses it to seed the *first* `failedRef`); this
reuses it every round. Degenerate case needs no guard: a round that wrote
nothing has nothing staged, and `commitDiff` returns the parent SHA, so
`head` correctly stays put.

**cells:** unchanged this iteration (0 new captures at fix time).

**model:** n/a.

**evidence:** red-then-green proven by temporarily reverting only the new
`head =` line:

```
# with the line reverted:
✘ Suite RepairLoopTests failed after 0.479 seconds with 1 issue.
# with the fix restored:
✔ Test validationFailedRoundWorkSurvivesIntoNextRound() passed after 0.547 seconds.
✔ Test validationFailedReceiptRetriesWithFreshEvidence() passed after 0.528 seconds.
✔ Test nonValidationFailedReceiptStillEndsLoopImmediately() passed after 0.260 seconds.
$ swift test                          # 538 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test  # 538 tests, 74 suites — passed
```

The permanent regression test is `validationFailedRoundWorkSurvivesIntoNextRound`
(round 2 writes ONLY `b.txt`, so it cannot pass by re-doing round 1's `a.txt`
— the blind spot that let the existing neighbouring test stay green through
the whole defect).

**next:** **measure** — both dominant blockers (V3: 39 cells, V1: 19 cells)
are now fixed and green. Dispatch one fresh Mellum pipeline cell and audit it.

## 5 — 2026-08-26 — measure (n=1)

**did:** Ran one fresh Mellum pipeline cell (abs/on/seed 1, the same
configuration as the overnight matrix) and audited the resulting capture
`20260826-085813-roadmap` against V1–V5.

**cells:** valid=**1** blocked={} of 1 new. **First valid Mellum pipeline
cell in the project's history** — cumulative valid Mellum cells now 2
(this one, plus `20260826-065840` from the matrix, which was valid only by
accident of dying in an uncovered way).

**model:** 0/1 among valid cells (NOT the goal) — acceptance exit=2,
verdict `bad`, 10 reasons. But the *shape* changed completely, which is what
this iteration was for.

> **CORRECTED by iteration 6.** Both numbers above are harness artifacts, not
> model results. `acceptanceExit=2` is the *pre-repair* grade; repair actually
> reached **exit=1, 7 failed / 6 passed**. The `verdict: bad` and its 10
> reasons were computed against a tree that excludes every repair round. The
> honest line is "repair reached 6/13 passing; the recorded verdict grades a
> tree that predates it." Recording a harness-distorted number as a model
> result is exactly what this goal exists to prevent, and it happened here on
> the first measure iteration.

**evidence:**

```
$ python3 audit_v1_5.py  (single-cell)
VALID
```

Directive now matches its own evidence, verified per packet:

```
repair-phase1/repair-packet-1.json | multi-file directive: "6 of the files you may edit are missing or wrong" | one-file: False | actually missing: 6
repair-packet-1.json               | multi-file directive: None | one-file: True | actually missing: 0
repair-packet-2.json               | multi-file directive: None | one-file: True | actually missing: 0
```

Mellum acted on it — 6 labeled blocks across the run, 5 distinct files
(`app.py`×2, `models.py`, `templates/home.html`, `templates/complaints.html`,
`tests/test_app.py`), where every overnight cell emitted exactly one file per
round and quoted the old directive to justify doing so.

Grade progression, and the headline change:

```
phase-1 repair round 1: candidate, validation exit=0   (matrix: 18/40 burned BOTH rounds here on validationFailed)
acceptance repair round 1: exit 1 — "7 failed, 6 passed, 13 warnings"
acceptance repair round 2: exit 1 — "7 failed, 6 passed, 13 warnings"
```

**6 of 13 tests passing, and a repair round saw real failing assertions for
the first time.** In the entire 80-cell overnight matrix, no Mellum repair
round was ever shown a failing assertion — every one got a bare collection
error. V2 (the collection gate) still fires on the *initial* acceptance grade
(exit=2, `AttributeError: module 'models' has no attribute 'complaints'`),
which is why the run still ends `bad`: repair spends its rounds getting the
suite to collect at all, then exhausts.

**next:** **fix** — V2 is now the binding constraint, exactly as the verdict
record's serial-not-parallel warning predicted. Note rounds 1 and 2 produced
*identical* grades (7 failed / 6 passed both times), meaning round 2 added
nothing: worth checking whether that is the model repeating itself or a
second, subtler discard. Fix V2 (surface more than one pytest error per
round) **with** the whole-packet budget the verdict record requires, since
the one cell that ever got a rich failure surface died on context overflow.

## 6 — 2026-08-26 — audit (investigation) — **ESCALATION**

**did:** Investigated iteration 5's identical-grades anomaly (rounds 1 and 2
both `7 failed, 6 passed`). The anomaly itself is benign and fully explained.
The investigation uncovered a **separate, previously unnamed harness defect**
that no frozen invariant covers — escalating rather than adding a V6.

**The anomaly: explained, not a bug.** Round 2 made a real, correct change
that was simply test-neutral:

- round 1 emitted `models.py` adding `complaints: List[Complaint] = []`,
  clearing the collection gate (exit 2 → exit 1, 6 tests passing)
- round 2 emitted `app.py` switching `from models import Complaint` to
  `from models import Complaint, complaints` and dropping app's duplicate
  local list — **the exact holistic cross-file fix Mellum reasoned its way to
  and then abandoned in the overnight matrix**, now actually made
- both lists were empty, so no test outcome changed

Grade outputs differ only in object memory addresses and timing (verified by
normalized diff), i.e. semantically identical. The remaining 7 failures are
all *content* requirements (seed-complaint text and count, nav links, add
form, tagline, UTC timestamp), which no amount of refactoring reaches.

Also checked and cleared: the 6-file multi-file harvest parsed correctly, no
heading text leaked into any file body.

**The defect: the final verdict grades a tree that excludes all repair work.**
In `main.swift`, the acceptance-repair `.exhausted` branch sets only
`repairNote` — it never updates `gradeWorktree`, which still points at
`failedWT`, the pre-repair implement-chain tree. Everything downstream is
then computed from that stale tree: `code.md`, the DeepSeek `verdict.json`,
and `acceptance.txt`. The `.passed` branch is correct (it sets
`gradeWorktree = wt`); only exhaustion is affected.

**evidence:**

This run (`20260826-085813`) — round 1 added `complaints` to `models.py`, and
`code.md` does not have it:

```
=== code.md models.py ===          | === what round 1 wrote (packet-2 evidence) ===
from dataclasses import dataclass  | from dataclasses import dataclass
from datetime import datetime      | from datetime import datetime
                                   | from typing import List
@dataclass                         | @dataclass
class Complaint:                   | class Complaint:
    agent_name: str                |     agent_name: str
    text: str                      |     text: str
    timestamp: datetime            |     timestamp: datetime
                                   | complaints: List[Complaint] = []   <-- absent from code.md
```

Predates today's fixes — matrix cell `20260826-060458`, where repair *created*
`models.py` from nothing across two rounds:

```
$ grep -o '^=== .* ===' captures/agenttest/20260826-060458-roadmap/code.md
=== app.py ===

$ verdict.json reasons mentioning models.py:
  - Missing seed complaints in models.py
```

The grader was handed a tree containing only `app.py`, then faulted the run
for what was missing from a `models.py` that repair had already written.

**Scope.** Every Mellum cell that reached acceptance repair and exhausted —
21 of 40 in the overnight matrix, and 0 of those passed, so all 21 — carries a
`verdict.json` and a reported `acceptanceExit` computed against a pre-repair
tree. The qualitative verdict data in
[`2026-08-26-overnight-80-cell-verdict.md`](2026-08-26-overnight-80-cell-verdict.md)
systematically understates what repair produced. The exit-code totals
(Laguna 39/40, Mellum 0/40) are unaffected: no run's *pass/fail* flips,
because a run that exhausted repair did not pass either way.

**cells:** no new captures. Iteration 5's cell stays valid=1; its recorded
model numbers are corrected in place above.

**Why this is an escalation, not a V6.** `/goal` freezes the invariant list
specifically so a run cannot be re-scored against rules invented after seeing
its data. V1 covers round-to-round survival; nothing covers "the verdict is
computed on a tree that excludes repair." Adding V6 mid-goal is the exact
move the rule forbids. It also needs a human decision that is not mine to
make: on exhaustion, should the verdict grade **the best tree repair reached**
(most informative about the model, and what `RepairLoop`'s `head` already
points at) or **the tree the run delivered** (defensible as "the run failed —
score what it shipped")? The current behavior is neither by design; it is an
un-updated variable.

**next:** **stopped, pending human decision** on the grading-tree question
above. Once decided, the fix is small and belongs with a red-then-green test
asserting `code.md`/`verdict` reflect repair's last candidate. V2 (the
collection gate, plus the whole-packet budget it requires) remains the next
fix after that.

## 7 — 2026-08-26 — audit (correction) — **retracts the headline of entries 5 and 6**

**did:** Fable review of the whole P16 loop. Two of the five invariant checks
were broken; one of them had certified the loop's headline result. Rewrote the
auditor, proved every check against a known-bad *and* a known-good cell, and
re-ran. The auditor now lives in the repo at
[`Tools/audit-goal-invariants.py`](../../../Tools/audit-goal-invariants.py)
rather than a session scratchpad, so these numbers stay reproducible.

**RETRACTED — "the first valid Mellum pipeline cell."** `20260826-085813` is
**blocked by V2**, the invariant it was reported as satisfying. V2 reads: *"no
round's **evidence** may contain `Interrupted:` with `error during
collection`."* The evidence is the packet the model was dispatched. The old
`check_v2` grepped `repair-round-N.json` — the grade recorded *after* each
round — which is off-by-one in both directions: it never inspects round 1's
dispatched evidence, and it does inspect a final-round grade shown to nobody.
The cell's actual round-1 packet:

```
$ python3 -c "import json; t=json.load(open('captures/agenttest/20260826-085813-roadmap/repair-packet-1.json'))['taskText']; print('Interrupted:' in t and 'error during collection' in t)"
True
```

Entry 5 even wrote the contradiction in prose — "V2 (the collection gate)
still fires on the initial acceptance grade" — in the same entry that recorded
`blocked={}`. The number and the sentence disagreed and the number won.

**This was predictable, not unlucky.** With V2 unfixed, *any* cell reaching
acceptance repair was guaranteed a collection-error round-1 evidence block. The
measure iteration could not have produced a valid cell. GPU was spent measuring
the harness, and the result was written down as a model result — the exact
failure this goal exists to prevent, now twice in one session.

**V4 is UNAUDITABLE, not passing.** `check_v4` could never fire under any
input: it passed if *any* packet contained `## Phase`, and `packet.json` always
does. Worse, `main.swift:716` captures only `phases[0]`, so phase 2/3 briefs are
never in the capture at all — V4 as written cannot be executed against these
runs either way. It now reports UNAUDITABLE, which is not a pass.

**Corrected cell counts** (`Tools/audit-goal-invariants.py`, self-test passing):

```
=== laguna: 38 valid / 40 total ===
    blocked:     {'V3': 1, 'V5': 1}
    unauditable: {'V4': 40}   (NOT passes)
=== mellum: 1 valid / 40 total ===
    blocked:     {'V1': 19, 'V3': 39, 'V2': 21, 'V5': 1}
    unauditable: {'V4': 40}   (NOT passes)

=== 20260826-085813-roadmap: BLOCKED ===
    V2: acceptance: repair-packet-1.json: dispatched evidence is a bare collection error
```

**Cumulative valid Mellum cells: 1** (not 2) — `20260826-065840`, valid only by
accident of dying in a way V5 does not catch. **Progress toward the goal of 10
is 1, and none of it was earned this session.**

**What still stands from entries 2–6,** re-verified: the V1 and V3 code fixes
are mechanically correct and live-confirmed (round 1's write visible in round
2's dispatched evidence; the multi-file directive dispatched and Mellum emitted
5 distinct files). The grading-tree escalation is exact — mechanism at
`main.swift:981–983`, scope exactly 21 cells, no pass/fail flips by
construction. Both suites pass, 538 tests. `check_v1`'s 19 reproduces from
receipts — though entry 1's claim that 19 "matches the verdict record" is wrong
on provenance: that record says 18 (a first-defect-to-fire partition); 19
appears nowhere in it.

**Commit `db7c914`'s message overclaims** and cannot be rewritten (already
committed): "the whole 80-cell overnight matrix produced 0 valid cells" is false
(Laguna 38, Mellum 1), and "first valid Mellum pipeline cell in the project's
history" is false twice over — it contradicts entry 1, and the cell is not
valid. This entry is the correction of record.

**next:** **replan** — the contract let a broken check certify a headline, and
had no rule that would have caught it. `.claude/commands/goal.md` is being
rewritten before any further iteration.

## 8 — 2026-08-26 — fix (grading tree)

**did:** Resolved iteration 6's escalation with the human's decision: **on
repair exhaustion, grade the best tree repair reached.** `RepairLoop.Outcome`
gained `BestReached(ref:grade:worktree:)` on the `.exhausted` case — the API
change Fable correctly flagged as necessary, since `.exhausted` previously
carried no candidate at all and the ledger's "one-line `gradeWorktree` update"
was wrong.

"Best" is implemented as **the last candidate**, and that is a claim, not a
shortcut: since the V1 fix, rounds are cumulative, so the final candidate
contains every prior round's work and is strictly the most complete tree repair
produced. Deliberately *not* implemented as a scored comparison across rounds —
there is no principled metric for it (pytest exit 1 vs 2 is not an ordering,
and "7 failed" vs "3 failed" is not in the exit code), and inventing one would
be exactly the kind of unfalsifiable judgment these invariants exist to keep
out.

The loop keeps the best candidate's worktree alive between rounds, discarding a
superseded one the moment a newer candidate replaces it, and hands it over live
on the same ownership contract as `.passed`. Both non-consuming callers
(`PhaseRepair`, whose exhaustion stops the run before any verdict; and the
fixture tier) now discard it explicitly rather than leaking it.

`main.swift`'s acceptance branch now sets `grade`, `acceptanceExit`,
`gradeWorktree`, and rewrites `acceptance.txt` from the best tree — so
`code.md` and the qualitative verdict finally describe what the model produced.
The run's pass/fail is unchanged by construction: `g.passed` short-circuits to
`.passed`, so an exhausted repair never carries a passing grade.

**cells:** no new captures this iteration.

**model:** (omitted — fix iteration, per contract.)

**evidence:** red-then-green, by temporarily reverting only the three lines
that record `best`:

```
# reverted:
✘ Test exhaustionReturnsTheBestTreeReached() recorded an issue at RepairLoopTests.swift:115:25
  ↳ exhaustion dropped the best tree reached
# restored:
✔ Test exhaustionReturnsTheBestTreeReached() passed after 0.525 seconds.

$ swift test                          # 539 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test  # 539 tests, 74 suites — passed
```

The test writes `a.txt` in round 1 and `b.txt` in round 2 and never passes, so
the returned worktree must contain **both** files — it cannot be satisfied by
the base tree or by either round alone.

**next:** **probe** — a fresh pipeline cell to confirm the fix end-to-end in
the live path. Explicitly a probe and not a measure: V2 is still unfixed and
still predicted to fire on any cell reaching acceptance repair, so no model
numbers may be recorded from it.
