# Failure classification: plural-fix and depth-3-estimation arms

Pre-registered secondary-endpoint analysis. Every non-pass cell from the two
post-plural-fix follow-up arms is classified into exactly one of the four
buckets defined in `experiment-manifest-depth3-estimation.tsv` rule 4:
`fewer-files-than-diagnosed` (delivery-class), `wrong-file-set-or-diagnosis`,
`content`, `format-collapse`. Classification is based on reading
`repair-round-*.json` (receipt/grade) and the reconstructed model text from
`wire.ndjson` for every failing/void capture — not on the harness receipt
alone.

No engine runs were made. This is pure capture analysis.

## Method note: the harvested wire text

`wire.ndjson` records are streamed tokens (`t:"text"`, field `s`). The full
per-round model text was reconstructed by concatenating all `text` events in
order and reading the diagnosis prose plus every `#heading` / fenced-code
pair. Where a round's text contains multiple diagnosis-then-emission passes
(the model second-guessing itself mid-turn), the *last* pre-emission
"here are the fixes" list was treated as the model's real final commitment,
compared against what was actually emitted.

## Classification table

| Arm | Fixture | Seed | Capture | Class | Evidence |
|---|---|---|---|---|---|
| pluralfix | depth-3 | 5 | `20260829-102317-fixture-depth-3` | **fewer-files-than-diagnosed** | Final list: "1. Timestamp... 2. Redirect... 3. The HTML structure might need adjustment for proper parsing" — then emits only app.py + models.py (+ an unrelated complaints.html); base.html is never emitted. |
| pluralfix | depth-3 | 8 | `20260829-102829-fixture-depth-3` | **content** | Says "Change `datetime.now` to `datetime.now()`" but the emitted `models.py` block is byte-identical to the buggy original (`field(default_factory=datetime.now)`); base.html and app.py fixes both landed correctly. |
| pluralfix | depth-3 | 10 | `20260829-103158-fixture-depth-3` | **content** | Correctly diagnoses "there's no `<html>` tag" in base.html, but the emitted fix is `<html>` with no `lang` attribute — same AttributeError persists. |
| pluralfix | depth-3 | 11 | `20260829-103417-fixture-depth-3` | **content** | Diagnoses `RedirectResponse("/complaints")` causes 307; "fix" is `RedirectResponse(url="/complaints")` — no `status_code=303`, so 307 persists (wrong belief that adding `url=` alone changes the status code). |
| pluralfix | depth-3 | 12 | `20260829-103625-fixture-depth-3` | **format-collapse** | `receipt={"contractNotFollowed":{}}`, no grade. Wire shows all 3 diagnosed files attempted, but the *first* occurrence of each heading is malformed (`` ``` `` then bare `templates/base.html` then `` ``` ``, no `#` heading line) — a uniform format defect, not a selectively-dropped file. |
| pluralfix | plausible-wrong-fix | 5 | `20260829-104336-fixture-plausible-wrong-fix` | **format-collapse** | V6 void ("1 heading had fenced code discarded... ['app.py']"). Wire shows a spurious `### app.py` + ` ```diff ` SEARCH/REPLACE block ahead of the real, correctly-headed `#app.py` block. **Surprising: round 1's actual grade (in `repair-round-1.json`) is 13/13 pass** — the harness's strict discard rule voided a candidate that would otherwise have graded clean. |
| estimation | depth-3 | 31 | `20260829-112054-fixture-depth-3` | **content** | Same "`RedirectResponse(url=...)` alone yields 303" wrong belief as seed 11; status_code never set, 307 persists. |
| estimation | depth-3 | 33 | `20260829-112423-fixture-depth-3` | **wrong-file-set-or-diagnosis** | Model reasons through base.html twice ("it has `<!DOCTYPE html>` and `<html>` tags, so that should be fine"), and its own final "Let me make the fixes" list narrows to app.py + models.py only — a conscious (wrong) diagnosis that base.html doesn't need touching. |
| estimation | depth-3 | 37 | `20260829-113114-fixture-depth-3` | **format-collapse** | V6 void ("2 heading(s) had fenced code discarded... ['app.py','models.py']"). Wire shows the *first* occurrence of each block malformed (`` ```\n# models.py `` — filename as an in-fence comment, no heading line), while later occurrences of the same two files are correctly headed. Compounding: model also explicitly said "The template files look correct, so I won't change them" (base.html), a second, independent diagnosis failure layered under the format defect. |
| estimation | depth-3 | 38 | `20260829-113347-fixture-depth-3` | **wrong-file-set-or-diagnosis** | Diagnosis narrows to "files that need to change: 1. app.py 2. models.py"; attempts to fix the lang issue by passing `{"lang": "en"}` as template context in `app.py` — base.html/its templates never reference `{{ lang }}`, so this does nothing. Wrong file (and wrong mechanism) targeted for the real bug. |
| estimation | depth-3 | 42 | `20260829-114029-fixture-depth-3` | **content** | Round 2's own text self-corrects three times; its *final* app.py block does carry `status_code=303`, but the graded round-2 result still shows the redirect test failing — an earlier, unfixed app.py duplicate earlier in the same turn is what got graded. Right file, wrong content reached the grader. |
| estimation | depth-3 | 44 | `20260829-114507-fixture-depth-3` | **content** | Same no-op fix as seed 8: states "I need to fix... use `datetime.now()`" but emits `field(default_factory=datetime.now)` unchanged. |
| estimation | depth-3 | 45 | `20260829-114725-fixture-depth-3` | **format-collapse** | V6 void naming app.py/models.py, same malformed-first-occurrence pattern as seed 37. Also drops the html-lang fix from its final list ("The most likely issues are: 1... 2..." — html omitted), a compounding diagnosis failure. |
| estimation | depth-3 | 46 | `20260829-114934-fixture-depth-3` | **fewer-files-than-diagnosed** | V5 void (`stop_reason=limit`). Emits app.py + models.py early, then enters a verbatim repetition loop that correctly re-derives "the `base.html` template doesn't have a `lang` attribute" dozens of times but never emits the file before the token budget runs out. Diagnosed, never delivered — same defect shape as the original bug, different proximate cause (generation loop, not a single-file emission cap). |
| estimation | depth-3 | 47 | `20260829-115313-fixture-depth-3` | **wrong-file-set-or-diagnosis** | Explicit final words: "Point 1 might be a separate issue with the test parsing, but I don't have the test code to fix that" — misattributes the html-lang failure to the test harness itself and commits to only 2 files. |
| estimation | depth-3 | 49 | `20260829-115650-fixture-depth-3` | **wrong-file-set-or-diagnosis** | Final "Let me fix these files: 1. models.py 2. app.py" — html issue dropped after being named in the initial diagnosis. |
| estimation | depth-3 | 52 | `20260829-120148-fixture-depth-3` | **content** | Correctly diagnoses base.html is missing `<html>` entirely, correct target, but emits `<html>` with no `lang` attribute (same as seed 10). |
| estimation | depth-3 | 53 | `20260829-120350-fixture-depth-3` | **wrong-file-set-or-diagnosis** | Final list narrows to app.py + models.py; emits an unrelated `templates/complaints.html` instead of the actually-needed base.html. |
| estimation | depth-3 | 54 | `20260829-120600-fixture-depth-3` | **content** | Diagnoses the redirect bug correctly, then "fixes" it by editing `tests/test_app.py` (not even the graded `test_acceptance.py`) to expect 307 instead of 303, while app.py's `RedirectResponse("/complaints")` is emitted unchanged/still-buggy. |
| estimation | depth-3 | 55 | `20260829-120826-fixture-depth-3` | **format-collapse** | V5 void (`stop_reason=limit`). Pure repetition loop from the first turn — **zero** headings or fenced blocks ever appear in the wire text. Genuine headingless collapse. |
| estimation | depth-3 | 60 | `20260829-121635-fixture-depth-3` | **content** | Regression: changes correct-shaped `field(default_factory=datetime.now)` to `timestamp: datetime = datetime.now()` (drops `default_factory` entirely), which fails a *different* assertion (`default_factory is not MISSING`) than the original failure. Right file, actively worse content. |
| estimation | depth-2 | 26 | `20260829-122604-fixture-depth-2` | **format-collapse** | `receipt={"contractNotFollowed":{}}`. Same malformed-heading pattern as pluralfix seed 12 — bare fence wrapping the filename, no `#` prefix anywhere in the transcript, applied uniformly to both diagnosed files. |
| estimation | depth-2 | 28 | `20260829-122901-fixture-depth-2` | **wrong-file-set-or-diagnosis** | See discrepancy note below. Model attributes the html-None failure to routes being declared `async def` (unrelated), "fixes" it by stripping `async`, and edits `tests/test_app.py` (wrong, ungraded file) — never touches base.html or emits any `<html>`/`lang` content at all. |
| estimation | depth-2 | 29 | `20260829-123102-fixture-depth-2` | **wrong-file-set-or-diagnosis** | See discrepancy note below. Explicit: "Looking at the templates, I don't see any issues with the `<html>` tag... since the redirect test is the most clear-cut issue, I'll focus on that." Only app.py emitted; base.html never touched. |

## ⚠ Discrepancy vs. the two pre-confirmed seeds

The task brief stated depth-2 seed 28 and seed 29 (estimation arm) were
already confirmed as **content** — "the model added an `<html>` tag but not
`lang="en"`." Reading both captures' actual `wire.ndjson` text directly
contradicts this:

- Neither capture's model text contains the string `<html` or `lang="en"`
  anywhere (verified by direct substring search over the concatenated wire
  text, not just by skimming).
- Seed 28's model attributes the failure to `async def` route handlers and
  "fixes" it by removing `async`, then re-emits an unrelated
  `tests/test_app.py`. It never touches `base.html`.
- Seed 29's model explicitly inspects the templates, concludes "I don't see
  any issues with the `<html>` tag," and deliberately skips it in favor of
  the redirect fix. It also never touches `base.html`.

Both grade the same two tests failing (`test_home_html_element_declares_english_language`,
`test_complaints_board_preserves_the_shared_layout`) with the same
`AttributeError: 'NoneType' object has no attribute 'casefold'` signature the
brief described — so the *test-level* symptom matches. But the underlying
model behavior is a diagnosis failure (never identifying or touching the
real cause), not an incomplete-fix-in-the-right-file case. I classify both as
**wrong-file-set-or-diagnosis**, not content. This should be re-checked
against whatever the live triage was actually looking at (it's possible a
different pair of captures, or an earlier/different round, was the basis for
the original note) before treating either number as final.

## Totals

| Class | Count |
|---|---|
| fewer-files-than-diagnosed (delivery-class) | **2** |
| content | 9 |
| wrong-file-set-or-diagnosis | 7 |
| format-collapse | 6 |
| **Total** | **24** |

Breakdown of the 2 delivery-class hits:
- pluralfix / depth-3 / seed 5
- estimation / depth-3 / seed 46 (via generation-loop exhaustion, not the
  original single-file-cap mechanism)

## Verdict on the pre-registered prediction

**Prediction:** delivery-class (`fewer-files-than-diagnosed`) ≤ 1 total
across both arms combined.

**Result: NO — refuted.** Count is **2**, not ≤ 1. The plural fix did not
fully extinguish the delivery defect: seed 5 (pluralfix arm) shows the
model's own final, pre-emission diagnosis naming three files, with only two
delivered, structurally identical to the original bug. Seed 46 (estimation
arm) shows the same shape (diagnosed-but-undelivered file) via a different
proximate mechanism — the model gets stuck in a verbatim repetition loop
and runs out of turn/token budget before it can emit the file it had
correctly (and repeatedly) identified as needing a fix.

That said, both hits are borderline in different directions: seed 5's
"drop" happens amid a single coherent turn (closest to the classic bug),
while seed 46's is arguably a distinct root cause (budget exhaustion in a
degenerate loop) that only resembles delivery-class in its *outward shape*
(diagnosed N, delivered <N). Even excluding seed 46 as a different failure
mode, the count is 1 — right at the boundary — so the honest reading is
"not cleanly resolved," not "clearly refuted by a wide margin."

## Other notable findings

1. **The dominant failure mode is not delivery — it's a recurring
   "self-talked out of the correct diagnosis" pattern.** 7 of 24 failures
   (33, 38, 47, 49, 53, 28, 29) show the model correctly naming the
   html-lang issue in its *initial* pass over the failure output, then
   explicitly reasoning itself out of it in a second pass ("that should be
   fine," "I don't have the test code to fix that," "I don't see any
   issues with the `<html>` tag") and never emitting the file. This is a
   distinct, larger population than the classic delivery bug and looks
   like the next thing worth targeting.

2. **A "graded-the-wrong-duplicate" artifact (seed 42).** When a round's
   text contains multiple self-corrected attempts at the same heading, the
   graded candidate did not match the model's own final, corrected block —
   consistent with the harness harvesting the *first* occurrence of a
   heading rather than the last. Worth confirming against the harvester
   implementation; if true, a model that catches and fixes its own mistake
   mid-turn can still fail the round.

3. **A false V6 void (plausible-wrong-fix seed 5).** The underlying
   round-1 grade was 13/13 passing, but a spurious diff-style pseudo-heading
   ahead of the real, correct blocks tripped the harness's discard rule and
   voided the whole cell. The harness is stricter than the actual code
   quality here.

4. **Malformed-heading format-collapse has a specific, repeated shape.**
   Across 5 of the 6 format-collapse cases (12, 26, 37, 45, and to a lesser
   extent the plausible-wrong-fix V6), the defect is not "no heading at
   all" but a heading written without a leading `#` (bare filename inside
   or before its own fence) — usually only on the *first* occurrence of a
   file that later gets a correctly-headed repeat. This looks like a
   distinct, nameable sub-bug in the model's heading formatting under
   repetition, separate from the pure-repetition-with-zero-blocks case
   (seed 55).

5. **An active regression (seed 60).** The model changed already-closer-to-
   correct code (`field(default_factory=datetime.now)`) into strictly worse
   code (`datetime.now()` as a plain default, dropping `default_factory`
   altogether), apparently confused by the polarity of the test's own
   assertion message. Not seen in the earlier Block B analysis's failure
   taxonomy.

## Files read

All classifications are based on `repair-round-1.json`, `repair-round-2.json`
(where present), and `wire.ndjson` under
`captures/agenttest/<capture>/` for each of the 24 captures listed above,
plus `repair-packet-1.json` for the plausible-wrong-fix contract text.
