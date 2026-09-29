# SwiftStar P29.10 design: folder, model and context menus

**Date:** 2026-09-29  
**Status:** design, approved in chat by the owner (option A, 2026-09-29)  
**Phase:** P29 — Make the front-end honest (step P29.10; revises P29.9's toolbar)

## Goal

The toolbar capsule shows three menu buttons — folder, model, context — and
the model menu lists the engine's real model choices, taken from ds4-engine
itself so SwiftStar keeps no registry.

## Decisions

1. **Three menu buttons** replace P29.9's folder button, model/context label
   and "Restart to use …" button:
   - **Folder** (label: the workspace's leaf name). Items: up to 5 recent
     workspaces (most recent first, current one ticked), a divider,
     "Choose Folder…" (the existing open panel).
   - **Model** (label: the loaded model id, else the Settings id, else
     "Engine default"). Items: "Engine default" (with the engine's
     `default_model_id` in parentheses when known), a divider, one item per
     engine model — ticked when it is the Settings choice; disabled with the
     reason ("not on this Mac", "doesn't fit", "not usable in the TUI") when
     it cannot run — then "Other…" (type an id).
   - **Context** (label: "<n> ctx" of the loaded session, else of Settings,
     else "Default ctx"). Items: "Engine default" (with the model's
     `default_context` when known), the model's measured sizes, then 8,192,
     16,384, 32,768, 65,536, 131,072 up to (and excluding sizes above) the
     largest size SwiftStar can justify: measured sizes are always listed;
     round sizes are listed only up to twice the largest measured size;
     then "Custom…".
2. **Choosing restarts.** Picking a different folder, model or context
   writes Settings (`agentWorkspace`, `engineModelID`, `engineContextSize`)
   and restarts the session when one is running; the menu choice is the
   confirmation. `restartNeeded` and the Restart button are removed.
3. **The list comes from the engine.** At launch (and when the engine path
   changes) SwiftStar runs `<ds4-dogfood> models --json` off the main actor
   with a 10 s timeout and decodes schema_version 1 (shape in the chat request
   of 2026-09-29, recorded below). Unknown keys are ignored; a different
   `schema_version`, a non-zero exit, a timeout or undecodable output fall
   back.
4. **Fallback.** Without a list the Model menu shows "Engine default", the
   current id (ticked) and "Other…"; the Context menu shows "Engine default",
   the current size, the round sizes up to 65,536 and "Custom…". Nothing
   else changes; no error dialog (a one-line note in the transcript at start:
   "Model list unavailable: <reason>").
5. **Settings window** keeps the engine path; the Model and Context fields
   move out of Settings (the menus own them).

## `ds4-dogfood models --json` (schema_version 1)

Top level: `schema_version` (1), `gpu_budget_bytes` (int|null),
`saved_model_id` (string|null), `default_model_id` (string|null),
`models` (array). Each model: `id`, `display_name`, `family`, `on_this_mac`
(bool), `path` (string|null), `downloadable` (bool), `fits` (bool|null),
`default_context` (int|null), `measured_contexts` (array of
`[context, plan_gib]`), `interactive` (bool). Requested from ds4-engine on
2026-09-29; SwiftStar ships against a recorded sample fixture and the
fallback until the engine command lands.

## Testing

- Fast tier (Kit): decoding the sample JSON (a fixture file written from the
  shape above), unknown keys ignored, wrong `schema_version` → fallback;
  pure menu-model builders — `ModelMenu.items(list:settingsID:loadedID:)` and
  `ContextMenu.items(list:modelID:settingsContext:loaded:)` — covering ticks,
  disabled reasons, the round-size rule, and fallback lists; recent-folders
  list (dedupe, cap 5, most recent first).
- Integration: the fake engine answers `models --json` from a fixture (and an
  env flag makes it fail) — `EngineModelCatalog` loads it, and falls back on
  failure/timeout.
- Live: once ds4-engine ships the command, the menu lists its models.

## Success criteria

1. The capsule shows three menu buttons; each changes its setting and
   restarts a running session.
2. With the engine command, the Model menu lists every engine model with the
   right enabled/disabled state; without it, the fallback menus work.
3. `swift test`, `SWIFTSTAR_INTEGRATION=1 swift test`, `just app`,
   `just lint-docs` green.
