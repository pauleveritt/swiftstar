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
