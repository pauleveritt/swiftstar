# EN.2 plan: catch up to ds4-engine `a84b79bd`

[Spec](../specs/2026-10-17-en2-engine-catch-up-design.md), accepted by the
owner on 2026-10-17. The branch is `en2-catch-up`. Tasks 1–5 need no GPU.
Task 6 does, and it waits for the owner's go.

## Decisions

The spec's D1–D10, with one addition:

- **D7a.** `saved_model_id` is never sent either (`tui_cli.py:196-222`), and
  only tests read it. So it goes with the other unsent catalog keys.

## Tasks

1. **Kit: the new events (D1–D4, D6).**
   - `EngineEvent.swift`:
     - `case startup(EngineStartupPart, summary: String?)`, where
       `EngineStartupPart` covers `baseline`, `candidateReady`, `envSync`,
       `projectInstructions` and `indexPrimed`
     - `case conversationState(EngineConversationState)`
     - `case analysis([String])`
     - `EnginePrefixCache` gains `changed: [String]?` and `entryFillMs: Double?`
   - `EngineWireParser.swift` decodes the six kinds and the two fields.
   - `EngineTranscript.apply`:
     - a non-empty `summary` becomes `.system`
     - `conversationState` becomes `.system`, via
       `MetricsFormatting.conversationStateLine`
     - `analysis` becomes `.report`, with its lines fenced as code
   - `EngineMetricsState` gains `startup: EngineStartupInfo` and
     `conversationState`. Both reset on `.session`.
   - `MetricsFormatting`:
     - `prefixCacheLine` follows D3
     - `conversationStateLine(_:)`
     - `startupRows(_:) -> [(String, String)]`

   Tests in `EngineWireParserTests`, over lines copied from the engine's
   tests, one per assertion:
   - `startupKindsDecode`: each kind's fields and `summary`
   - `nullSummaryMakesNoRow`: the transcript is unchanged
   - `startupFoldsIntoMetrics`: `EngineStartupInfo` after all five
   - `conversationStateLines`: `loaded`, `failed`, `absent`, `unsupported`
   - `prefixLineSaysWhatChanged`: a miss with `[model]`, a miss with `[]`,
     and a hit with `entry_fill_ms`
   - `analysisBecomesAFencedReport`: `.report` starting with three backticks
2. **Kit: `git` and `test` cards (D5).**
   - `EngineToolCard.icon`: `git` is `arrow.triangle.branch`, `test` is
     `checkmark.seal`.
   - `EngineToolCard.resultLanguage` is `diff` for `git`; otherwise it's
     the path's language, as now.
   - `metadataLine` adds a `test` result's first line, without its brackets.

   Tests in `EngineTranscriptTests`:
   - `gitAndTestIcons`
   - `gitResultIsDiff`
   - `testCardShowsPytestLine`: `succeeded · 2.3s · pytest with the
     project's .venv: exit 0 in 2.3 s`
3. **Kit: the catalog (D7, D7a).**
   - In `EngineModelCatalog.swift`, `Model` loses `family`,
     `measuredContexts` and `runsInTUI`. `defaultContext` becomes
     `context`, and the model gains `sizeBytes: Int64?` and `planGiB: Double?`.
   - The list loses `savedModelID` and `defaultModelID`.
   - `ToolbarMenus.swift`:
     - **Model titles:** `Qwen3.8 27B — 15.7 GiB, plans 24.7 GiB`.
     - **Context menu:** "Engine default (131,072 · 24.7 GiB)". It lists the
       round sizes up to 65,536, plus the model's `context`.
   - `fixtures/engine/models.json` is rewritten to the engine's keys.

   Tests in `EngineModelCatalogTests` and `ToolbarMenusTests`:
   - `decodesTheEngineKeys`: `models-real.json`'s size and plan
   - `modelTitleNamesSizeAndPlan`
   - `contextDefaultNamesContextAndPlan`
   - `contextMenuAddsTheModelsContext`
4. **UI.**
   - The Session card in `InspectorView.swift` gains a Start-up group, from
     `startupRows`, and a "Saved state" row.
   - `ToolCardView` uses `resultLanguage`.
   - `PreviewFixtures` adds startup events, a `conversation_state`, and a
     `git` card and a `test` card.
   - **Rendered with `RenderPreview`:**
     - InspectorView "Running" and "Narrow"
     - the TranscriptRowView tool cards
   - **Gallery screenshot:** the model and context menus.
5. **Docs.**
   - ROADMAP's engine requests as in spec §2.
   - SU.7c's "blocked" line gets the finding, left for the owner.
   - `provenance.md` names the lines taken from the engine's tests.
   - CHANGELOG.
   - Both tiers.
   - Merging waits for Task 6.
6. **Recordings (GPU, after the owner's go).**
   - `just capture` for every scenario at `a84b79bd`, plus
     `resumed-answered`.
   - A session directory with key records, for `report.json`.
   - The fast-tier tests switch from the engine-test lines to the
     recordings.
   - `provenance.md` pinned. Then the close: ROADMAP, Result, merge.

## Result

Done 2026-10-18. Tasks 1–5 ran on 2026-10-17 with no GPU, and Task 6 on
2026-10-18 after the owner's go.

- **Commits:**
  - `79e7273`: Task 1
  - `cc71390`: Task 2
  - `77f1812`: Task 3
  - `af72ea1`: Task 4
  - `1866984`: Task 5
- **Tests:**
  - `just test` (195) and `just integration` (86) pass.
  - Every new behavior was broken and its test failed. That's 11 in Task 1,
    3 in Task 2 and 4 in Task 3. A few mutants first failed to build
    (warnings are errors here), and were caught once rewritten so they did.
- **Diverged:**
  - **D7a:** `saved_model_id` also went.
  - **The model menu's title** is "Qwen3.8 27B (15.7 GiB, plans 24.7 GiB)",
    in parentheses, not after an em dash. The gallery showed a second em
    dash on a disabled row: "… 137.1 GiB — not on this Mac".
  - **The Session card's "Saved state"** drops the line's subject, which
    its label already says.
  - **The Task 1 tests** are in a new `EngineStartupEventsTests.swift`, not
    in `EngineWireParserTests`.
  - **Fixture controllers take a `catalog`**, so the gallery's menus have
    titles to show.
- **Previews and gallery:**
  - Rendered and looked at:
    - InspectorView's "Running", "Narrow" and the new "Resumed"
    - ToolCardView's new "git and test"
    - SessionView's "Running"
  - In the gallery's real window, opened through System Events: the model
    menu and the context menu, with "Engine default (131,072 · 24.7 GiB)".
- **For the owner:**
  - The `test` card reads "succeeded · … exit 1": the tool ran, and the
    tests failed. That's accurate, but a reader may take it for a pass.
  - D1 adds up to three rows before the first prompt.
  - SU.7c may not be blocked (spec §5).

### Task 6: recordings

- **Time:** about 2 minutes of GPU on the 27B, against my estimate of
  10–15. Most of it was `tool-read` (22 s), `resumed-answered` (29 s, three
  sessions) and nine `tool-rejected` attempts (about 20 s each).
- **Re-recorded at `a84b79bd`:** `tool-read`, `stop`, `error`,
  `relaunch-rewind` and `resumed`.
- **New:** a `resumed-answered` scenario in `Tools/record-engine-fixture.py`.
  It recorded:
  - `prefix-changed.ndjson`: a real miss with `changed: ["context"]`
  - `resumed-answered.ndjson`: `conversation_state` `loaded`, 0.3 GiB in
    23 ms, then "4 + 4 = 8."
  - the session directory `fixtures/sessions/20261018-112154-su-ui`, with
    its `report-resumed.json`

  This closes the AN follow-up's fixture. Done's return test over it is not
  written.
- **`tool-rejected` stays hand-written.** It always was (my earlier note
  that it was recorded was wrong). At `a84b79bd` the 27B tripped no loop
  guard on seeds 1–5 or 7–9. The event's shape is unchanged.
- **What the real data changed:**
  - **Sub-second times read in ms.** A 23 ms load read "0.0s", so
    `shortDuration` now serves both the state line and the Start-up rows.
  - **The report's Conversation state row** shows the engine's label alone.
    The real `/2` label carries size and time ("conversation state loaded:
    305 MiB in 0.02 s"). My synthetic test had a bare label, so it printed
    them twice. That test is replaced by one over `report-resumed.json`.
  - **"1 prompts"** in the Continues row is now "1 prompt".
  - **Three pinned values moved:** the resumed answer ("2 + 2 is 4."), the
    prefix's tokens (944 to 1,333, now that CLAUDE.md is in it) and the
    session directory's name.
- **Tests:** three `EngineStartupRecordingTests` over the recordings.
  `just test` (198) and `just integration` (86) pass. The three new
  behaviors were each broken, and their tests failed.
- **Commits:** `1866984` (Task 5), then this close.

