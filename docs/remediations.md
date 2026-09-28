# Remediations

The changes actually made against [`pathologies.md`](pathologies.md), ranked
by measured impact. Companion to that list: pathologies are what we saw,
these are what we did about it and whether it worked.

Source files cited here by name (`LabeledBlockParser.swift`,
`RepairLoop.swift`, and the rest of the repair harness) were removed in P28;
the commit hashes still resolve in git.

**Every entry carries its denominator.** A remediation that was built but
never measured says so in those words; a remediation that was measured and
did not work is kept here, in its own section, because knowing a lever is
dead is worth as much as knowing one is live. Numbers are quoted from the
research notes and commit bodies cited on each entry, not recalled.

**The ranking is judgment, not measurement.** These come from two projects,
two model families, and two harnesses, so the effect sizes are not strictly
comparable. The denominators are there so the order can be argued with.

## The fifteen

### 1. (System Prompt) State the technology stack as fact

*Pathologies 26, 10.* Naming Python/FastAPI/Jinja2 and "`app.py` at the
project root, exposing a module-level object named `app`" — with the task
spec deliberately untouched, pinned by a drift test.

**0/16 → 15/16** on the user-story suite (facts-only arm, n=16). At the n=6
pilot scale, grader-accepted went 0/6 → 0/6 → **5/6** across cycles 5/6/7,
and Flask errors 5 → 5 → **0**. The largest measured lever in either repo.
*(local-ai-pi `improvements/tech-stack-only/stack.md`, `37cd7bf`; cycle 11
decomposition.)*

### 2. (System Prompt) State the empty workspace as fact

*Pathology 25.* "The workspace is empty… Do not spend turns searching for
files: listing the directory will keep returning nothing, because there is
nothing there."

Worst single-command repetition **245 → 1**; runs containing a repeated
identical tool call **15/16 → 0/6**; most tool calls in one run 261 → 7.
Caveat recorded in the source doc: the two cycles ran under different time
caps and the *rates* are not comparable — the collapse in repetition is.
*(`70c35f5`; `2026-08-04-phase5-cycle5`.)*

### 3. (Harvest) Lenient parse of unfenced headings

*Pathology 5.* An allowlisted `#path` heading not immediately followed by a
fence now still yields a file body, because the bodies were complete and
EOS-terminated and differed from a pass only by missing fence lines.

Build arm `contractNotFollowed` **3 of 4 → 0 across 9 runs**; repair arm
**4/4 at 13/13**; 3 of 9 build runs reach 13/13 on the real acceptance suite
with 0 tool calls. Dissolved an earlier "model scores 1/4" — *the number was
measuring the parser, not the model.* Attribution check: the first post-fix
run emitted zero fences across all three phases and still reached 13/13.
*(`LabeledBlockParser.swift`, `1a8314a`; `2026-08-25-p15-verdict-record.md`.)*

### 4. (Agent Environment) Hermetic child via `PI_CODING_AGENT_DIR`

*Pathology 25.* The delegated child had been loading the operator's own
`~/.pi/agent/extensions/`, including one that rewrote `ls -R` into a
size-annotated listing of everything under cwd including all of `.git`. The
child read a large unhelpful answer, learned nothing, and asked again.

Timeouts **2/6 → 0/6**, worst repeated command **178 → 5**, median run
transcript **9.63 MB → 0.49 MB**, peak context **2.8M → 91k tokens**. The
loop breaker refused zero calls — the repetition stopped happening rather
than being caught. *(`2da8b8e`, `1e8eb41`.)*

### 5. (Engine) Degeneracy-guard threshold

*Pathology 11.* A trailing single-byte run is now measured against
`AGENT_DEGENERATE_BYTE_RUN` (256) before the unit loop, and the loop skips
one-byte spans; multi-byte units keep the 64-byte floor. A `unit == 1` floor
alone would not have fixed it — a one-byte run also matches at unit 2/4/8/16.

Before: **5 of 5 consecutive cells voided**, every one ending on a dash run
of exactly 64. After: **zero degeneracy-guard aborts across 10 captures**.
Unit table of 13 cases; boundary clean at 255 vs 256.
*(`ds4_agent.c`, pin bumped in `a4d0256`; fork-ledger row 15.)*

### 6. (Oracle/Grader) Grading rules 4–8

*Measurement integrity.* Preservation and oracle run in separate workspaces;
named vs position-keyed node inventories split; damage outranks a scope
violation; writing tests is no longer a scope violation; a skipped oracle
test is no longer an accept.

Rule 5's ceiling replay found **rule 4 had failed the reference answer on 4
of 9 tasks**, because Sybil node ids are position-keyed and one inserted
production line reads a correct candidate as having deleted tests. Rule 7
regraded **two banked candidates from out-of-scope to accepted at zero model
calls**, and corrected a control that had been restricting the reference
patch until it passed. Rule 8 verified latent-not-live: all 43 banked
accepts already had `tests_passed == target_total`, 0 outcomes changed.
Impact is on the validity of every other number in this file.
*(`4658c64`, `2cf6cd5`, `b17ac85`, `4663b49`, `54f6d27`.)*

### 7. (RepairLoop) Make rounds cumulative on `validationFailed`

*Adjacent to pathology 4.* `finalize` only committed on `.candidate`, so each
round's write was discarded when its worktree was torn down — "N rounds" was
N independent single-shot attempts.

**18 of 40** cells of the overnight matrix died there; one case wrote
`app.py` and `models.py` that import cleanly together and never survived
together. Fixed with a red-then-green regression test and confirmed live.
No after-rate — the value is that it made multi-round evidence mean
anything. *(`RepairLoop.swift:248-272`, `db7c914`.)*

### 8. (Context Assembly) Carry project context into the orchestrate directive

*Pathology 10.* The framework pin already lived in `specs/tech-stack.md`; the
directive path simply never passed `sharedContext` into the prompt, though
the non-directive phase loop always had.

**4/4 runs lost to an entire app rebuilt in Flask → 0 substitutions across
10 captures.** Caveat: the resulting graded rate of 6/9 = 67% [35%, 88%] has
a CI overlapping the 27/29 = 93% baseline, so the substitution is eliminated
but the overall rate is not established — "real signal, underpowered."
*(`OrchestrateDirective.build`, `8414b28`.)*

### 9. (Handoff Packet) Multi-file repair directive

*Pathologies 1, 17.* The directive unconditionally asserted "Exactly one file
is wrong" / "do not add new files". A computed missing-file count now selects
a multi-file directive at `count >= 2`; `count <= 1` keeps the old text
byte-identical.

The false clause was wrong in **39 of 40** cells. Same fixtures, same model,
same seeds, only the directive changed: depth-2 **0/3 → 2/3**, depth-3
**2/3 → 3/3**. Small n, and the headline this arm produced ("editing 15/17,
depth flat") was later overturned by a larger arm at 38/56 with a monotone
depth slope — the commit itself concedes it was "an n=3 upper-tail draw."
*(`db7c914`; `2026-08-26-p17-repair-limit-verdict.md`.)*

### 10. (Handoff Contract) The locating contract

*Pathologies 22, 24.* Naming the real target file and its writable scope
instead of a prose brief.

At n=8/arm: `autowire` candidate-created **1/8 → 8/8**;
`stringified-annotations` oracle-passed **3/8 → 8/8**, Newcombe difference
[0.170, 0.863]. Caveats: pooled across four tasks the difference is
[-0.076, 0.367] and **includes zero**; two tasks were at a ceiling or floor
in both arms; and the `registry-iter` contract that scored 5/6 was found to
contain the complete solution verbatim, so that cell does not count.
*(`db33752`; `2026-08-11-phase7-cycle7-confirmatory-result.md`.)*

### 11. (Host Tool Execution) Honor read windows

*Pathology 20.* The host ignored every window parameter and condensed at 8000
bytes, making the middle of any file over 8 KB unreachable — a starvation
loop, not simple redundancy.

Paired control, only `readResult` reverted: **12 read/more calls on one file,
timed out at 240 s, failed at prompt 1 of 12 → 3 calls, ~33 s, 12/12 prompts
in 4.5 min.** Against the baseline: read/more **76 → 16**, repeat rate
1.45 → 1.00, compactions 5 → 1. **Stated weaknesses, from the doc itself:**
the numeric thresholds were revised after seeing the data they then cleared
and must not be cited as pre-registered; n=1 session per arm; the control
never reached prompt 2, so there is no paired token bill; and the protocol
lived in an ephemeral scratchpad with the control branch deleted, so
**neither arm is re-runnable from the repo**.
*(`HostToolExecutor.readResult`, `0ce679c`.)*

### 12. (Handoff Packet) Count-free plural emission follow-up

*Pathology 1.* "the heading line for **each file** you just diagnosed… Emit
every file you diagnosed, however many that is." Deliberately states no
count — naming a number would repeat entry 9's defect inverted. The old
wording is restorable byte-identically on the same binary as a concurrent
control.

Depth-2 **12/19 (63%) → 12/12**; depth-3 **8/18 (44%) → 7/12**, and 25/40 =
62% [47%, 76%] on a separate 40-cell estimation arm. **Reported as not a
win:** the pooled pre-registered endpoint came in at **19/24, p = 0.059** —
missed its bar by one cell, recorded as underpowered. The pre-registered
secondary endpoint was **refuted**: delivery-class failures were predicted
≤1 and came in at 2 of 24. The dominant residual mode is now pathology 2, at
7 of 24 failures. *(`f5aa1f6`; `2026-08-29-p26-closure-verdict.md`.)*

### 13. (Mutation Engine) Symbol-preservation check

*Pathology 24.* Refuse an edit whose `oldText`s name a `def`, `class`, or
route decorator absent from every `newText` of the same call.

**1/4 → 4/4**, guard fired in 3 of 4 runs (Fisher p = 0.14 two-tailed; n=4
was the cap, and the doc says so). Replay: 5 refusals in 5,711 calls across
344 streams. The pre-edit guard version was later **removed** — it had no
visibility into `HandoffContract.removableSymbols` and could refuse a
contract-authorized rename before the engine, the only place those are
admitted, ever ran. The mutation engine's `lostSymbols()` is now the sole
gate. *(`85f018a`, wired `38298d8`, removed `b4f95c1`, `220c319`.)*

### 14. (Handoff Contract) Fix structurally unsolvable contracts

*Harness defects that were being graded as model failures.* `autowire`'s
oracle imports `from svcs import autowire, aautowire`, which is unsatisfiable
unless `__init__.py` is writable — the contract was unsolvable before the
fix. `flask-extensions`' base `test_flask.py` directly asserts the *old*
behavior in exactly the two tests that kept failing, so a correct fix
necessarily fails them, and the model may only write production code.

`autowire` candidate-created **0/2 → 4/4**. `flask-extensions` **0/6 across
two pilot rounds → 3/4 candidate-created, 3/3 real-oracle-passed.**
*(`247e91e`, `432a3e3`.)*

### 15. (System Prompt) State the subagent call shape literally

*Tool-call malformation, the class of pathologies 7 and 23.* The prompt now
names `agent`, `task`, `agentScope` literally, with the parameter names read
from the framework's own schema and pinned by three static assertions —
because the validator tests `hasSingle = Boolean(agent && task)` and every
rejected call had sent `{agentScope, task}`.

**4 rejections across two cycles, each producing no child → 8 subagent calls
across 6 runs, every one carrying `agent`, zero rejections.** *(`70c35f5`.)*

## What was measured and did not work

Kept because a dead lever is worth knowing.

- **(Repetition Guard) The loop breaker.** Measured four times live and
  null-to-negative each time: primary threshold **failed** on the svcs
  cohort (loop deaths 2/6 against a bar of 0, `loop_broken` entries 0, while
  the longest identical consecutive runs were 42 and 58); **0/6 vs 0/6** with
  zero firings on the user-story suite. Its share of the composite
  0/16 → 13/16 is **explicitly zero**. A run where it fired 4 times still
  ended `tests-vanished, delta -30`. Its offline "zero false positives across
  55 healthy runs" and "would have blocked 239 of 261 calls" figures were
  **retracted** — the fixtures were built from an event that includes calls
  never reaching the hook.
- **(System Prompt) Rules of conduct.** "Do not run the same command over and
  over" failed all three of its pre-registered predictions. "The packages are
  pre-installed" failed three predictions and made things **worse**: pip
  calls 28 → 37, with 5, 6 and 7 installs in single runs against a prior
  maximum of 3.
- **(Contract-Authoring Prompt) Relaxing the mechanism prohibition.** Meant
  to fix pathology 27; **replaced partial engagement with total collapse** —
  oracle 0/8, all-noop 8/8, against hand 8/8 (Fisher p = 0.0002).
- **(Mutation Engine) No-op refusal alone.** Correct and worth keeping for
  legibility, but the re-run still timed out with nothing written, and the
  refusal is **evadable** — the model answered it by appending a blank line.
- **(Context Budget) Raising the token cap.** 8192 → 16384 moved `autowire`
  from truncation to a *targeting* error ("not a fix, a different wall").
  8192 → 32768 took accepts 17% → 37.5%, landing exactly on the prespecified
  reject threshold, and exposed a new mode: continuing past the fix into
  throwaway diagnostic scripts.
- **(Engine) Tool-initiation nudge.** On Mellum, **0 tool calls in every
  nudge cell**. On Laguna XS it flipped one task from a 30-minute
  no-initiation timeout to 13/13 — n=1.
- **(Packet Gate) `inspectContract`.** 862 lines cut to 380 against
  pre-registered delete rules. Its `mechanism_specificity` metric ranked the
  0/4 document above the 1/3 one; `missing_facts` rejected the good corpus
  more than the doubtful one. Only the deterministic path-existence rule
  survived, ported to a lint with no model in it.

## Built but never measured against the pathology

`--think-budget` and per-turn think on the wire (pathology 16 — the
regression test was deferred, "no local model reproduces visible thinking");
the writable-scope injection into the authoring prompt, which is the direct
fix for pathology 28 and has no post-fix run; `proposal-limit.ts`, which
never had anything to check; the fence-beats-prose harvest fix (before-only:
6 of 6 lenient headings discarded code in one capture, 3 of 8 cells carried
non-compiling files); the rewritten text-contract directive; contract-file
parser hardening; `bumped_max_tokens`.

## Proposed and never built

A pre-validation block for schema-invalid tool calls — **structurally
unreachable** by any tool-call hook, since a validation failure returns
before the hook runs; it needs a change in the agent core. The "stop after
the fix is written" guard (three transcripts, no design). Disambiguating the
orchestrate directive's dispatch ordering (pathology 9). Making
`contractNotFollowed` consume a round instead of aborting. A grammar for
placeholder tool-call syntax and think-state-aware constraint for tool calls
inside `<think>` (pathologies 7, 8) — the engine's existing corrective nudge
is explicitly *not* the remedy. **Pathology 15 has no fix at all**: the
harvester still implements first-occurrence-wins.

## The rule the record itself draws

Across five prompt interventions, the three that supplied a **fact the model
lacked** worked — the stack, the empty workspace, the call shape, at ranks 1,
2 and 15. The two that supplied a **rule of conduct** failed every
pre-registered prediction, and one made its target metric worse. There is no
coaching sentence on the top-fifteen list, and that is not an accident.

The second rule, from four tabulated silent-zero incidents: **a suspiciously
clean zero is an instrument fault until the instrument is checked.** Ranks 3,
5, 6 and 14 are all cases where the instrument, not the model, was producing
the number.

---

*Provenance: ranks 1, 2, 4, 10, 13, 14, 15 and most of the negative results
come from `local-ai-pi`'s phase 5/7/11 research notes and commit history;
ranks 3, 5, 7, 8, 9, 11, 12 and the P15/P17/P24/P26 material come from this
repo's `docs/superpowers/research/` and `ROADMAP.md`. Rank 6 is
`local-ai-pi`'s grading rebuild. Compiled 2026-09-01.*
