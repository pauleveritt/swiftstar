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
