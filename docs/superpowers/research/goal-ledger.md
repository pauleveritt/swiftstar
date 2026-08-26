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

## 9 — 2026-08-26 — probe (no model numbers permitted)

**did:** Two live pipeline runs to confirm the exhaustion-grading fix in the
real path. The first was inconclusive; the second confirmed it.

**Probe 1 (`20260826-100350`, abs/on/seed 1) — inconclusive.** Died in *build
phase 1*, before reaching the code under test, on an engine error not seen
before and covered by no invariant:

```
"state":"error","generated":467,"ctx_used":13507,
"error":"too many malformed tool calls in a row"
```

Mellum *attempted* tool calls here (4 `tool` events, 1 `tool_request`) and
produced malformed ones until the engine gave up — more evidence for P13's
"rare, not never". Same seed and config as `20260826-085813`, which completed
70 minutes earlier, so this is run-to-run variance, not a regression (the
changed code does not touch the build phase). The capture records this only as
a wire `status.error`; nothing in the schema names it. **Flagged, not
converted into a V6.**

**Probe 2 (`20260826-101531`, abs/off/seed 2) — confirms the fix.** A line
that has never appeared in this project's output before:

```
[agenttest] repair: exhausted — repairExhausted
[agenttest] repair: grading best tree reached — refs/swiftstar/candidates/F5D0D008-... (exit 1)
```

Structural confirmation, all three downstream artifacts now describing repair's
output rather than the tree that entered repair:

- `acceptance.txt` records `exit=1` (repair's grade). Every previously
  exhausted cell recorded the pre-repair grade instead.
- `code.md` contains **2 files** (`app.py`, `models.py`). All 20 graded matrix
  cells that exhausted contained exactly **1**.
- the verdict is computed against that 2-file tree.

**cells:** both probes audit **BLOCKED (V2)** — exactly as predicted before
running them. `20260826-101531`'s round-1 packet carries a bare collection
error, so V2 fires. Cumulative valid Mellum cells: still **1**.

**model:** (omitted — probe iteration. V2 was known to be unfixed and known to
fire on any cell reaching acceptance repair, so no number from these runs is
attributable to the model. This is the rule that iteration 5 lacked.)

**evidence:**

```
$ python3 Tools/audit-goal-invariants.py captures/agenttest/20260826-101531-roadmap
=== 20260826-101531-roadmap: BLOCKED ===
    V2: acceptance: repair-packet-1.json: dispatched evidence is a bare collection error
    V4: UNAUDITABLE — only phases[0] packet is captured (main.swift:716)

$ grep -o '^=== .* ===' captures/agenttest/20260826-101531-roadmap/code.md
=== app.py ===
=== models.py ===
```

**next:** **fix V2** — the last invariant blocking every cell that reaches
acceptance repair, and now the only thing between the loop and a real measure.
Per the verdict record and Fable's review it must ship *with* a whole-packet
budget: the one cell that ever received a rich failure surface died of context
overflow at 37,180 tokens against a 32,768 ceiling, so surfacing more errors
per round without capping the packet converts V2 blocks into V5 blocks.

## 10 — 2026-08-26 — fix (V2)

**did:** Fixed V2, the last invariant blocking every cell that reaches
acceptance repair. When pytest aborts collection, `AcceptanceGrader` now
replaces its output with an **enumerated precondition manifest**: it walks the
acceptance suite's own module-level AST and checks each requirement
independently, so one grade names every unmet gate instead of the first.

Derived from the suite rather than hardcoded — the suite is harness-owned and
may change, and a hardcoded gate list would rot silently.

Note what this does *not* do: `--continue-on-collection-errors`, the cheap
option the verdict record floated, would not have worked. There is only one
test module, so when its import fails there is nothing else to continue *to* —
pytest still reports one error. The gate chain had to be enumerated directly.

The exit code is untouched. This changes what the model is shown, never
whether a run passed.

**cells:** no new captures this iteration.

**model:** (omitted — fix iteration, per contract.)

**evidence:** red-then-green (fix disabled by short-circuiting its guard):

```
# disabled:
✘ Expectation failed  ↳ grade still shows a bare collection abort
# restored:
✔ Test collectionAbortIsReplacedByAnEnumeratedPreconditionManifest() passed after 0.577 seconds.

$ swift test                          # 540 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test  # 540 tests, 74 suites — passed
$ python3 Tools/audit-goal-invariants.py --self-test   # PASS
```

The test reproduces the real gate chain (`app.py` present, `models.py` absent)
and asserts the manifest names the attribute gate `models.complaints` that
pytest can never reach, and that the probe leaves nothing behind in the tree.

Run against the **real** acceptance suite, the manifest that replaces
`ModuleNotFoundError: No module named 'models'` is:

```
  [MET]   from dataclasses import MISSING
  [MET]   from dataclasses import fields
  [MET]   from starlette.testclient import TestClient
  [MET]   from turbohtml import Doctype
  [MET]   from turbohtml import parse
  [UNMET] from app import app -- AttributeError: module 'app' has no attribute 'app'
  [UNMET] import models -- ModuleNotFoundError: No module named 'models'
  [UNMET] from models import Complaint -- ModuleNotFoundError: No module named 'models'
  [UNMET] models.complaints -- ModuleNotFoundError: No module named 'models'

4 of 9 preconditions unmet.
```

Four gates in one grade. That whole chain is what consumed the entire two-round
budget in 21 of 21 cells.

**next:** **fix V5** — the whole-packet budget, before any measure. This is
now the binding risk rather than a theoretical one: with V2 fixed, more cells
will get *past* collection, and a cell that has all six files written plus a
full 13-assertion failure surface is exactly the shape that overflowed at
37,180 tokens against a 32,768 ceiling (`20260826-055741`). Fixing V2 without
the budget converts V2 blocks into V5 blocks. The contract's measure gate
already forbids measuring until it lands.

## 11 — 2026-08-26 — fix (V5)

**did:** Fixed V5 — and it was **not** the missing whole-packet budget the
prior entries, the verdict record, and Fable's review all assumed. Measuring
the overflowing packet's composition before writing any code showed the
assumption was backwards:

```
total taskText bytes: 85421
  directive+spec :  3534
  failure output : 80807
  file contents  :  1080     <- six files, ~1 KB total
```

The overflow was almost entirely *failure output* — which `outputCap` was
supposed to bound at 8192. The packet's own truncation note gave it away:

```
- failure output truncated: 88919 -> 80727 bytes
```

`MachineEvidence.cappedFailureOutput` kept **`byteCount - cap`** bytes instead
of `cap`. It walked backward decrementing the *remaining* count until that fell
under the cap, then kept everything it had walked past. Wrong in both
directions: it under-keeps below 2× cap (9018 bytes at cap 8192 kept 816) and
over-keeps above it (88919 kept 79826).

**Why three prior analyses missed it, including two of mine.** The existing
tests assert only `out.utf8.count <= cap` — which an under-sized result
satisfies — and every input they used was under 2× cap, where `byteCount - cap`
is itself under cap. The bug was invisible until a real 88 KB pytest run.

Effect on the cell that died (`20260826-055741`), same packet recomputed:

```
was 85421 bytes  ->  now <= 12844 bytes  (15.0% of the size that overflowed)
```

Comfortably inside the 32768 context. **No whole-packet budget is needed** —
the residual worst case is bounded by the existing text-contract guard, which
already refuses a round when any single writable file exceeds `fileCap`.

**cells:** no new captures this iteration.

**model:** (omitted — fix iteration, per contract.)

**evidence:** red-then-green, both halves of the bug pinned separately:

```
# before:
✘ (out.utf8.count → 79826) <= 8192   ↳ kept 79826 bytes for cap 8192 — the cap is inverted
✘ (out.utf8.count → 816) > 8128      ↳ kept only 816 of a possible 8192 bytes
# after:
✔ MachineEvidenceTests — 11 tests passed (including all 9 pre-existing)

$ swift test                          # 542 tests, 74 suites — passed
$ SWIFTSTAR_INTEGRATION=1 swift test  # 542 tests, 74 suites — passed
$ python3 Tools/audit-goal-invariants.py --self-test   # PASS
```

**One honest caveat:** the first integration run after this change reported
`✘ Test run with 542 tests ... failed with 1 issue` without naming the test,
and did **not** reproduce in four subsequent runs (three of them dedicated
attempts). Recorded as an unreproduced flake rather than a clean sweep. Not
escalating — the contract's trigger is a *default-tier* failure surviving a fix
attempt, and this was integration-tier and did not survive. Worth watching.

**next:** **measure** — and this is now legitimate under the contract's gate
for the first time. Naming the invariants a fresh cell will traverse and why
each is fixed: **V1** cumulative rounds (`head` advances via `commitForRepair`,
fixture-confirmed 13/13); **V2** the precondition manifest replaces collection
aborts (fixture-confirmed against the real suite, 4 gates named at once);
**V3** the directive branches on missing-file count (live-confirmed, Mellum
emitted 5 distinct files); **V5** the cap is no longer inverted (measured: the
packet that overflowed is now 15% of its former size). **V4 remains
UNAUDITABLE** — phase 2/3 packets are still uncaptured — so any cell it would
have judged must be reported as unauditable, never as passing.

---

## 12 — 2026-08-26 — measure (n=4) — **ESCALATION**

**did:** Ran the first measure batch whose gate was legitimately open — mellum
only, 2 seeds × 2 path styles, think off, 4 cells, binary at `410cf86`
(rebuilt, 8s newer than the newest fixed source). Audited before recording any
number. **Three of four cells are valid; the model failed all three.** Stopping
the loop: three separate escalation triggers fired.

**cells:** valid=3 blocked={V5:1} unauditable={V4:4} of 4
**Cumulative valid Mellum cells: 4 of 10** (3 new + `20260826-065840`,
re-audited VALID under the current auditor). Spread among the three new valid
cells: seeds {1,2}, paths {relative, absolute} — the goal's required spread is
met; only the count is short.

**model:** **0/3** among valid cells (NOT the goal). Computed from
`repair-round-N.json` grade records — the last graded round — never from
`acceptanceExit` or `verdict.json`.

**evidence:**

```
$ GOAL_MANIFEST=/tmp/measure-manifest.tsv python3 Tools/audit-goal-invariants.py
=== mellum: 3 valid / 4 total ===
    blocked:     {'V5': 1}
    unauditable: {'V4': 4}   (NOT passes)

$ python3 Tools/audit-goal-invariants.py --self-test
self-test: PASS          # 8/8 fixtures, re-run after making MANIFEST env-overridable

model: line, from round records only
  mellum/relative/seed1  20260826-104551  -> (blocked, excluded)
  mellum/absolute/seed1  20260826-104811  -> fail  (repair-round-2.json grade.exit=1)
  mellum/relative/seed2  20260826-105213  -> fail  (repair-round-2.json grade.exit=2)
  mellum/absolute/seed2  20260826-105529  -> fail  (repair-round-2.json grade.exit=1)
```

**The fixes are confirmed working in the pipeline, not just in fixtures.**

*V2 (precondition manifest).* Every acceptance packet dispatched in this batch
carried either the enumerated manifest or a real running-test surface. Zero
carried `error during collection`:

```
20260826-104811  repair-packet-1  7073B [manifest]   repair-packet-2  6770B [manifest]
20260826-105213  repair-packet-1  8582B [manifest]   repair-packet-2  8582B [manifest]
20260826-105529  repair-packet-1  5915B [manifest]   repair-packet-2 13590B [assertions]
```

A live manifest, naming the single unmet gate precisely instead of one opaque
`ModuleNotFoundError`:

```
  [MET]   from app import app
  [MET]   import models
  [MET]   from models import Complaint
  [UNMET] models.complaints -- AttributeError: module 'models' has no attribute 'complaints'
1 of 9 preconditions unmet.
```

*V5 (tail cap).* `20260826-105529`'s round-2 packet kept **8194 bytes** for a
cap of 8192 (one character boundary), and what it kept is the part that
matters — the pytest summary naming all 13 failing tests:

```
FAILED test_acceptance.py::test_complaint_model_contract_is_preserved - Asser...
FAILED test_acceptance.py::test_seed_complaint_count_is_preserved - assert 3 ...
13 failed, 13 warnings in 1.91s
```

Across the three valid cells, every turn ended `eos`; max `ctx_used` was 16878
of 32768. No context pressure anywhere.

**A corrected claim, before it was written down.** I was about to record
"105529 is the first dispatched packet in the project's history to carry a real
assertion surface." Scanning all 146 dispatched packets showed 14 qualify —
most of them Laguna. The accurate statement is narrower: **among Mellum cells,
one prior packet (`20260826-055741` round 2) carried an assertion surface and
was never delivered — it is the context-overflow cell V5 was fixed for — so
`105529` is the first *valid* Mellum cell in which a delivered packet named all
13 failing assertions and the model's answer to it was graded.** Mellum's
answer: `13 failed` → `13 failed`. No improvement.

**What the three valid cells actually show Mellum doing:**

- `104811` — round 1 stuck on the precondition; round 2 cleared it and the
  suite ran (`12 failed, 1 passed`). It reached the assertion surface exactly
  as the 2-round budget expired, so **it was never shown the assertions.**
- `105213` — shown one precisely-named unmet gate (`models.complaints`), it
  edited the *wrong file*: it put `complaints` in `app.py`. Both rounds'
  emissions are byte-identical (`1eb1ed6e4ccb`), and the emitted `app.py` is
  byte-identical to the `app.py` the packet had just shown it as current —
  a verbatim re-emission, which the directive explicitly forbids
  ("do not reproduce the current broken file").
- `105529` — dispatched the full 13-assertion summary, produced no improvement.

**On the identical packets in `105213`:** `repair-packet-1` and
`repair-packet-2` are byte-identical (`b264bde613fe`). This is *not* the V1
discard defect and the auditor's V1 pass is correct: V1's gate is a
`validationFailed` receipt, and both rounds produced candidates. The packets
match because the model re-emitted the current file verbatim, so the tree
content did not change. Whether `head` advanced is unobservable here — the
content is identical either way — and I am not claiming it was proven.

**Structural observation, recorded as an observation and NOT as a new rule:**
the harness minted a candidate ref for a byte-identical re-emission and spent a
round on it, twice. There may be a missing no-op check. That is a fix proposal
for the human, not something this iteration may adopt.

**next:** **STOP — escalate.** Three triggers, listed in the message to the
human. The loop does not choose here.

---

## 13 — 2026-08-26 — measure (n=4, budget=5) — **ESCALATION**

**did:** At the human's instruction, made the repair round budget
env-configurable (`AGENTTEST_REPAIR_ROUNDS`, default unchanged at 2; commit
`deb86bd`) and reran the same 4 cells at 5 rounds. **The rerun produced zero
model numbers and exposed two defects that the 2-round budget had been
structurally hiding.** Recommending no further GPU runs until the human rules
on them.

**cells:** valid=3 blocked={V1:1} unauditable={V4:4} of 4 — **but see below:
the V1 FAIL is a false positive, and I am NOT adding these 3 to the cumulative
count.** All four cells died in phase-1 repair without ever reaching
acceptance. **Cumulative valid Mellum cells stays at 4 of 10.**

**model:** (omitted — no acceptance round ran in any cell, so there is no
graded model result to report. `repair-round-N.json` exists only under
`repair-phase1/`.)

**evidence:**

```
$ GOAL_MANIFEST=/tmp/measure-manifest-r5.tsv python3 Tools/audit-goal-invariants.py
=== mellum: 3 valid / 4 total ===
    blocked:     {'V1': 1}
    unauditable: {'V4': 4}   (NOT passes)

$ ls captures/agenttest/20260826-112536-roadmap
packet.json  repair-phase1  run-config.json  validation-phase1.txt  wire.ndjson  wire.trace
        # no acceptance.txt, no verdict.json, no top-level repair-round-*.json — in all 4 cells

run-config.json of every cell: repairMaxRounds = 5      # plumbing confirmed live
```

Baseline (entry 12, 2 rounds): 3 of 4 cells reached acceptance. This batch (5
rounds): 0 of 4. **I am not attributing that swing to the budget** — see
defect 2, which makes the two batches not comparable.

---

### Defect 1 — `check_v1` disagrees with its frozen invariant's text [v2 escalation]

V1 reads: *"A round that ran **and wrote** must not be followed by a packet
showing the identical missing-file set."* `check_v1` gates only on the round
having **ran** (receipt `validationFailed`); it never establishes that the round
**wrote** the missing file. When a round runs and simply does not emit the
missing file, an unchanged missing set is correct behaviour, and the check
calls it a discard.

That is exactly what happened in `20260826-112121`:

```
turn 2: 3c1f7c4e6fad   headings=['app.py']
turn 3: d5329a63d9de   headings=['models.py','app.py','templates/...']
turn 4: 3c1f7c4e6fad   headings=['app.py']      <- identical to turn 2
turn 5: 3c1f7c4e6fad   headings=['app.py']
turn 6: 3c1f7c4e6fad   headings=['app.py']
```

`tests/test_app.py` — the file the auditor reports as "the write did not
survive" — **was never emitted by the model in any round.** The FAIL is a false
positive. This is the v2 contract's named escalation ("an audit check is found
to disagree with its frozen invariant's text") and it retroactively taints any
V1 count produced by this check on multi-round captures.

**A near-miss worth recording:** I first reasoned "the five receipts have five
different digests, so the tree changed each round." That inference is wrong.
Consecutive packets 4 and 5 differ by exactly one line:

```
-  File ".../swiftstar-wt-AAE9A953-.../app.py", line 42, in <module>
+  File ".../swiftstar-wt-4C01CE73-.../app.py", line 42, in <module>
```

Only the ephemeral worktree UUID. Digest inequality proves nothing about the
tree.

### Defect 2 — a fixed seed does not make a run reproducible

The repair packet embeds the per-round temp-worktree path inside pytest/import
tracebacks. Same seed, same path style, same spec, different invocation ⇒
different prompt ⇒ different sampling. Diffing the round-2 packets of
`20260826-104811` (baseline) and `20260826-112536` (rerun), both
mellum/absolute/seed1, shows they diverge from the traceback line onward — and
baseline round 2 **repaired** where the rerun round 2 failed.

Consequences: the budget comparison is confounded and cannot be read as
"budget=5 is worse"; prompt-prefix caching is defeated across rounds; and an
absolute host path is injected into runs whose entire purpose is a
relative-vs-absolute path arm.

### Defect 3 — the lenient harvest writes the model's prose into source files

`LabeledBlockParser.parse` has an explicit fallback: a heading with **no fenced
block** takes its body as everything up to the next allowlisted heading. In
`20260826-112536` round 1 Mellum emitted six headings, prose under each, and
**zero fences**, ending:

```
# tests/test_app.py

This file is missing, but the error is about the `app` module. ...

Now I'll create all the missing files with the appropriate content:
```

That is a *plan*, not code. The harness harvested it into six real files, so
`app.py` became English prose and every later round was repairing a file full
of the model's own commentary. Measured by compiling the `.py` contents the
packets show as current, across **both** batches:

```
2rounds relative seed1  20260826-104551  non-compiling .py: ['app.py','models.py','tests/test_app.py']
2rounds absolute seed1  20260826-104811  non-compiling .py: ['app.py','models.py','tests/test_app.py']
5rounds absolute seed1  20260826-112536  non-compiling .py: ['app.py','models.py','tests/test_app.py']
        (the other 5 cells: none)
```

**3 of 8 cells.** No invariant covers this, so per the contract it is an
escalation and NOT a new rule. It also plausibly explains the original brief's
whack-a-mole report.

The lenience is not an accident — it was added because P15 found a strict
parser was measuring the parser rather than the model. So reverting it is not
obviously right, and choosing among the options (require a fence always; ignore
a heading whose body is not code; treat an emission containing zero fences as
`contractNotFollowed` and harvest nothing; apply lenience only when the
emission contains at least one fence) is **a design decision with more than one
defensible answer — the human's call, not the loop's.**

**A hypothesis, explicitly not a conclusion:** since the V1 fix made rounds
cumulative, a bad round's damage now persists into every later round, so a
larger budget may compound damage rather than allow recovery. The
non-reproducibility in defect 2 means this batch cannot test that.

**next:** **STOP.** Three triggers: an audit check disagreeing with its
invariant, cells failing in a way no invariant covers, and a fix requiring a
design decision. No further GPU runs until the human rules.
