# Block B negative result — what actually happened, and what it overturns

**2026-08-29.** Analysis of the Block B editing re-measurement
([pre-registration](2026-08-28-overnight-campaign-preregistration.md),
[results](experiment-results-editing-n20.tsv)) against the P17 claim
([verdict](2026-08-26-p17-repair-limit-verdict.md)) that Mellum editing was
15/17 with a flat depth profile. Everything below is from files and captures on
disk; no cell was run or re-run.

## 1. Is the comparison sound? Verdict: yes — the overturn is real, not an instrument change

Checked, between P17 (2026-08-26) and Block B (2026-08-28/29):

- **Fixtures, reference tree, acceptance suite: byte-identical.**
  `git diff 'HEAD@{2026-08-26 23:59}' HEAD -- fixtures/agenttest/repair/{plausible-wrong-fix,depth-2,depth-3} fixtures/agenttest/reference fixtures/agenttest/acceptance`
  is empty. The only fixture-tree changes since P17 are the *additions* of
  `framing-2-edit` and `framing-2/.delete`, which Block B does not run.
- **The dispatched prompt: byte-identical.** The `taskText` of
  `repair-packet-1.json` in a P17 depth-2 capture (`20260826-133709`) and a
  Block B depth-2 capture (`20260828-232815`) diff to nothing. Same directive
  (the corrected, hedged multi-file one), same writable list, same contract
  text, same ctx_size (32768), same noThink (`AGENTTEST_THINK` unset in both;
  the P23 default think budget of 2,048 lives in `AgentDefaultSettings` — the
  app path — and never reaches `swiftstar-agenttest`, which reads
  `AGENTTEST_THINK_BUDGET`, default 0).
- **Runner and oracle: unchanged.** `Tools/run-experiment.py` last changed at
  `c140573` (v5 close-out, 2026-08-26, before Block B was registered);
  `RepairLoop.swift` likewise; `TextContractHarvest.swift` unchanged since
  `1a8314a`. Same `classify()` (pass = final graded round exit 0; V5/V6 voids
  excluded).
- **The singular emission follow-up (see §2) existed verbatim at P17** —
  `git show e9f5811:Sources/swiftstar-agenttest/main.swift` contains the same
  `repairEmissionFollowUp` text, and P17's own captures show the same
  headingless-turn → single-file-follow-up shape (e.g. `20260826-130402`,
  `20260826-133837`). Same instrument, both days.
- **What did change: the engine binary.** The `external/ds4` pin moved from
  `1091a39` to divergence #14 (`ae0b75f`), and `AgentCommand.argv` now always
  passes `--per-turn-think`. The fork diff (`1091a39..HEAD`) touches only
  `ds4_agent.c` (the agent wire/CLI shell, +482/−38) plus the fork ledger —
  not the sampler or inference core files. The harness sends no per-turn
  override, and the wire shows the same engine defaults in both runs. This
  could in principle perturb token-level sampling at a given seed, but the two
  runs share no seeds anyway, so only a *systematic* behavioural shift would
  matter, and no mechanism for one is visible in what changed. I cannot prove
  a null from disk; I can say the observed failure mechanism (§2) is present
  in P17's own captures under the old binary, which is the strongest available
  evidence that the instrument did not change in the way that matters.

**The rounds-pooling question, quantified.** P17's rounds=2 editing subtotal
was **8/8** — *better* than its pooled 15/17. Block B pinned rounds=2. So
pinning the budget at 2 cannot explain any of the drop; the sign is wrong. If
Block B's per-fixture rates (0.95 / 0.63 / 0.44) are the truth, the
probability of P17's rounds=2 subtotal coming out 8/8 is
0.95³ × 0.63² × 0.44³ ≈ **0.029** — P17 drew an upper-tail sample at n=3, an
unlucky-lucky 1-in-34 event, which its own scope section half-anticipated
("directional, not precise"). Note also the pooled comparison 15/17 vs 38/56
is only marginally incompatible (one-sided Fisher p ≈ 0.086): what Block B
decisively overturns is not "Mellum can edit" but the **flat depth profile**.
95% → 63% → 44% across 1→3 files is monotone and the 1-file vs 3-file
intervals ([75,99] vs [25,66]) do not overlap.

## 2. What the model is actually failing at

Mined all 18 graded-fail captures plus the passing cells of the same fixtures.

### The dominant mechanism: correct multi-file diagnosis, single-file delivery

Every one of the **7 depth-2 failures** (seeds 6, 8, 15, 19, 20, 21, 22) has
the identical wire shape:

```
turn 1: reasoning + fences, ZERO heading lines  -> harvest: 0 labeled blocks
turn 2 (emission follow-up): "#app.py" + one block -> only app.py applied
round 2: near-verbatim replay of round 1 -> "#app.py" again
grade: FAILED test_home_html_element_declares_english_language
       FAILED test_complaints_board_preserves_the_shared_layout   (both rounds)
```

The model *diagnoses both files correctly in every one of these cells*. Seed 6,
turn 1, verbatim: *"1. In `base.html`, add `lang=\"en\"` to the `<html>` tag.
2. In `app.py`, change `RedirectResponse(\"/complaints\")` to
`RedirectResponse(url=\"/complaints\", status_code=303)`"* — followed by a
**complete, correct `base.html`** and a complete, correct `app.py`, both in
fences **with no heading lines**. The packet's contract ("A fenced code block
with no preceding heading line is ignored") discards both; then the emission
follow-up fires — and its text is **singular**:

> "Now emit it. Your entire response must be the heading line for **the file
> you** just diagnosed, followed by **one fenced code block** containing
> **that file's** complete corrected contents…"

This is written for the single-file case, and in a two-file diagnosis it acts
as a subtler version of P17's "exactly one file is wrong" defect: the model
obeys it and emits exactly one file. In seeds 6/19/21 the discarded turn-1
fences contained the full correct base.html fix; in 8/15/20/22 turn 1 stopped
at eos before or without a usable base.html block (seed 20 ends *"Let me make
these changes: … Here are the changes:"* — then eos, zero applicable blocks),
but the two-file diagnosis is present in all seven.

**Round 2 is then wasted by self-copy.** The round-2 packet demonstrably
carries fresh evidence — for seed 6, `repair-packet-2.json` shows app.py
already fixed and only the two base.html tests failing — yet the model's
round-2 turn is a **byte-identical** replay of round 1 at seed 6, and a
near-verbatim replay (same "three test failures" opening, cosmetic diffs
only) at seed 20. It re-diagnoses failures the evidence says are gone and
re-emits app.py. Rounds are cumulative in `RepairLoop` (the 2026-08-26
D-fix is in place and working — round 1's app.py *did* survive into round 2's
tree; the old "discards work on validationFailed" finding is fixed, see
`RepairLoop.swift:248-272`), but a round the model spends replaying itself
buys nothing.

**Why the passing cells pass.** Depth-2 passes come in exactly three shapes:
turn 1 emits headed blocks itself (s7, s10, s12); the follow-up emits *both*
files despite the singular ask (s4, s5, s13, s18, s23); or — the revealing
one — the follow-up picks **base.html** in round 1 and app.py in round 2
(s11, s14, s16, s17). One file per round is survivable at depth 2 if the two
picks differ; every failing cell picked app.py **twice**. At depth 3 the same
regime is arithmetic death: 3 files, 2 rounds, one file per round (seeds 4, 5,
18 fail exactly this way).

### The rest of the taxonomy (18 graded fails)

| class | cells | count |
|---|---|---|
| Single-file delivery of a correct multi-file diagnosis (heading discard + singular follow-up + round-2 replay) | d2: 6,8,15,19,20,21,22; d3: 4,5,18 | **10** |
| Genuine content/reasoning failure | d3: 10, 11, 13, 14; pwf: 15 | **5** |
| Target-selection failure (headed emission, wrong file set) | d3: 16 | **1** |
| Format/contract collapse | d3: 7, 19 | **2** |

The genuine failures are worth naming because no harness fix touches them:

- **d3 s11 (twice), s13**: the timezone contract. Round 1 emits all three files
  with headings — and `models.py` is the *broken original*, verbatim
  (`default_factory=datetime.now`). Round 2, with the assertion in front of
  it, reasons *"It should be `datetime.now()` (with parentheses) to return a
  datetime with timezone"* — false — and re-emits the same broken line.
  `test_complaint_model_contract_is_preserved` fails in both rounds.
- **d3 s14**: diagnoses all three defects in turn 1, then talks itself out of
  the HTML one (*"the templates all extend base.html which has a `<html>` tag,
  so that should be fine. The main issues appear to be the two I've
  identified"*) and never emits base.html.
- **pwf s15**: the one single-file editing failure with a graded round — round
  2 edits `tests/test_app.py` instead of `app.py` (writable, but the graded
  suite is the acceptance suite; a classic fix-the-test move).
- **d3 s7**: re-emits all six writable files (against "do not reproduce a file
  that is already correct"), breaks the import, `validationFailed` both
  rounds — so no graded round ever exists. **d3 s19**: emits heading
  `base.html` instead of `templates/base.html`; the harvest rejects it and the
  loop returns `.exhausted` on `contractNotFollowed` **without consuming the
  remaining round** (`RepairLoop.swift`, the `.receipt` path: only
  `validationFailed` continues; every other receipt aborts).

A misreading that recurs across cells but rarely decides them: the model reads
`AttributeError: 'NoneType' … casefold` as "the `<html>` element is None / the
HTML is not being parsed", rather than "`html.attr(\"lang\")` returned None",
and wanders into DOCTYPE/viewport theories (s8's turn 1 invents a
`width-device-width` typo). When it nonetheless lands on "add `lang=\"en\"`"
— which it usually does — the misreading is harmless.

## 3. What would actually help — ranked

1. **Fix the singular emission follow-up.** One prompt string
   (`repairEmissionFollowUp`, `Sources/swiftstar-agenttest/main.swift:229`):
   make it count-aware or plural — "for **each file** you diagnosed, its
   heading line followed by one fenced block". This is the same class of
   defect P17 fixed in the directive, one layer down, and the evidence says it
   gates ~10 of 18 failures. Cost: one line + a pre-registered re-run of the
   depth-2/depth-3 configuration at fresh seeds (≈40 cells, ~2–3 h of engine
   time by Block B's per-cell times). What it proves: how much of the 63%/44%
   is harness amplification vs model. Risk: it is prompt-tuning — pre-register
   it as an A/B against the frozen Block B numbers and do not touch anything
   else, or the comparison inherits every confound the pre-registration warns
   about. Prediction to hold it to: depth-2 fails whose turn 1 contained a
   complete correct base.html (s6/s19/s21-type) convert to passes; the
   timezone cells (s11-type) do not move.
2. **Stop discarding complete correct fixes over a missing label.** When a
   turn yields 0 labeled blocks but ≥1 fence, the harvest currently throws the
   content away and re-asks. Options in ascending ambition: (a) make the
   follow-up quote back the file names the model itself listed ("You named
   base.html and app.py; emit both, each under its heading"); (b) heading
   inference — match an unlabeled fence to a writable file by language +
   near-identity to an existing file's structure, guarded by V6-style
   auditing. (a) is a prompt change and composes with fix 1; (b) is harness
   code with real misattribution risk (V6 exists precisely because harvest
   bugs have burned this project before). Do (a) first.
3. **Make `contractNotFollowed` consume a round instead of aborting the loop**
   (s19 died with budget unspent), and normalise `base.html` →
   `templates/base.html` when the basename uniquely matches a writable file.
   Small, cheap, worth ~1–2 cells per campaign at most — do it opportunistically,
   not as the headline fix.
4. **On more rounds: P17's "no" does not survive, but buy the fix first.**
   Under the one-file-per-round regime, rounds ≥ files-to-fix would mechanically
   help depth-3 (s4/s5/s18). But the round-2 self-copy shows extra rounds are
   low-yield while the replay attractor persists — seed 6 would have replayed
   round 3 as surely as round 2. If fix 1 lands, rounds=2 may simply suffice;
   measure that before spending rounds. If a rounds arm is run anyway, add to
   the round-N packet one sentence the model currently has to infer: "Your
   previous corrections to <files> are already applied; do not re-emit them."
5. **Name the real ceiling honestly.** After the harness-amplified cells are
   netted out, what remains at this fixture tier is roughly 5–6 of 56 graded
   cells (~10%): the timezone-contract misfix (twice, with the assertion in
   hand), dismissing a correct diagnosis, editing the test instead of the app.
   That is the current best estimate of Mellum's genuine per-cell content
   failure rate on these editing tasks — and it is failure to *derive or
   commit to the right edit*, not failure to make multi-file edits. Nothing
   found in these captures suggests a prompt fix for it; if the re-run after
   fixes 1–2 still shows a depth slope, that slope is the model and the
   project should plan around ~90% per-file-set editing reliability, not 95%+.

**Not implicated:** the edit-application path (every harvested block was
applied faithfully; no case of a harvested file landing wrong), the
`validationFailed` work-discard (fixed; verified live in RepairLoop and in the
seed-6 packet-2 evidence showing round 1's work present), the evidence shape,
and the oracle.

## What cannot be determined from disk

- Whether the divergence-#14 engine binary shifts Mellum's output distribution
  at all. Settling it costs 6 preflight-seed cells on the old binary — only
  worth it if the post-fix re-run behaves inexplicably.
- Why the follow-up's file pick lands on app.py vs base.html (the "file you
  just diagnosed" referent). The captures show both happen; the sample is too
  small to say what biases it.
- Whether P17's 8/8 was luck alone (p ≈ 0.03 under Block B's rates) or partly
  a binary effect. These are confounded by design; the pre-registration's own
  closing caveat applies.

## One stale memory

The standing note "RepairLoop discards work on validationFailed — '2 rounds'
is really 2 independent single-shot attempts" describes a defect **fixed on
2026-08-26** (`RepairLoop.swift:248` advances `head` via `commitForRepair`
every validation-failed round; Block B's seed-6 round-2 packet shows round 1's
app.py fix present in the tree). The finding should be retired or marked fixed.
