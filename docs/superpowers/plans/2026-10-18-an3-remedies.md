# AN.3 plan: remedies

[Spec](../specs/2026-10-18-an3-remedies-design.md), accepted by the owner on
2026-10-18 with D4 (a), and the live check on the owner's GPU go. The
branch is `an3-remedies`.

## The live check, first (2026-10-18)

The 27B was given the fixture session's report and the new instruction, in
a fresh session (a fork only resumes one), against the main checkout.

1. **Asked for an `agents-md` block, with "Don't edit files":** it explored
   the repository instead. That was 15 tool calls, one of them a read of
   this branch's AN.3 spec, and at one point it took a file's text for an
   "injected instruction". It ran out of context, and ended `tools-closed`
   with no answer, after 3 min 46 s.
2. **With "Answer from the report alone, without tools":** it answered in
   2 min 41 s. The answer explained the three flagged steps, then gave one
   `agents-md` block of three lines, in the **narration**. The `answer`
   was `finish`'s summary, without the block.

So D1 searches narration as well as answers, and the instruction keeps
"without tools". The model still called the first prompt's prefix-cache
miss "a cold-start cost", which is the misreading the engine's labels were
meant to prevent.

## Decisions

The spec's D1–D6, with D4 (a), plus:

- **D7.** `EngineAnalysis.instruction` takes run 2's wording.
- **D8.** The engine's suggestions come with the report:
  `SessionReportLoader` returns `AnalysisReport {markdown, suggestions}`.

## Tasks

1. **Kit.** In `Sources/SwiftStarKit/Remedies.swift`:
   - `Remedy {line, fromEngine: String?, alreadyThere}`
   - `Remedies.parse(rows:from:) -> [String]`
   - `Remedies.merged(model:engine:existing:) -> [Remedy]`
   - `Remedies.file(agentsExists:claudeExists:) -> String`
   - `Remedies.applied(to:lines:) -> String`
   - `Remedies.doneTitle(count:file:)`

   `EngineAnalysis.instruction` becomes D7's wording.

   Tests in `RemediesTests`, over the live narration
   (`fixtures/engine/analysis-remedies.ndjson`):
   - `parseFindsTheLiveBlock`: three lines
   - `noBlockNoRemedies`
   - `lastBlockWins`
   - `blockBeforeTheForkIsIgnored`
   - `mergedDedupesAndMarks`
   - `appliedAddsTheHeadingOnce`
   - `fileChoice`
   - `doneTitle`
2. **Engine and controller.**
   - `SessionReportLoader` returns `AnalysisReport`.
   - `EngineController` keeps:
     - the engine's suggestions
     - the instructions file's text, read at Analyze
     - `tickedRemedies`
     - pending lines at Done

     It applies them at the return's `resumed`, and clears them on any
     other end.
   - The fake engine refuses `/resume ID` with a relaunch.

   Tests:
   - `remediesAppliedAfterDone`: the temp repository's `AGENTS.md` and the
     row.
   - `remediesNotAppliedWithoutDone`: a quit in the fork leaves the file
     untouched.
3. **UI.**
   - A `RemediesCard` at the transcript's end while analyzing.
   - The banner's Done title.

   Previews rendered: the card (ticked, unticked, "already there") and the
   banner.
4. **Docs.** ROADMAP, CHANGELOG, provenance and both tiers.

## Result

Done 2026-10-18. The GPU was used only for the two live checks above.

- **Commits:**
  - `b1bad8c`: Task 1
  - `323c3cc`: Tasks 2 and 3, in one commit, since the controller and the
    views changed together
  - this close
- **Tests:**
  - `just test` (228) and `just integration` (94) pass.
  - **Kit:** every new behavior was broken, and its test failed: 9 in
    `Remedies` and 1 for the instruction.
  - **Controller:** applying on the return, the lines kept at Done, and the
    clear on any other end were each broken, and `remediesAppliedAfterDone`
    or `remediesNotAppliedWithoutDone` failed.
- **Found while building:**
  - **The block is in the answer's reply.** The live narration that holds it
    is absorbed into the answer row as its `reply` (SU.6a), so the reply is
    searched too.
  - **Done's return over the fake engine.** The fake now refuses `/resume
    ID` with a `resume_refused` relaunch, as the relay does, so the return
    is tested end to end. That's the AN follow-up's path, with the fork's
    fixture assembled from two recordings (`analysis-remedies.ndjson`).
  - **My mutation script misread integration runs as build errors,** since
    the fake engine's stderr says "error:". It now looks only for compiler
    errors.
- **Diverged:**
  - **The card shows each line without its list marker** (`Remedy.label`).
    The file gets the line as written.
  - **The card sits after the last row** of the fork, not under the answer
    that holds the block: a follow-up answer can replace the block.
- **Previews:** these were rendered and looked at:
  - the Remedies card: unticked, ticked with the engine's reason, and
    "already there"
  - the banner's "Done · add 2 lines to AGENTS.md"
- **Checked live by the owner, 2026-10-18:** the whole loop in the app,
  with an Analyze, ticks, Done and the file written, together with AN.2's
  click-through.

