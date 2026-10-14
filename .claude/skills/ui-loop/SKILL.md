---
name: ui-loop
description: >
  SwiftStar's edit → preview → test loop for SwiftUI work. Use when changing,
  adding or reviewing any file under Sources/SwiftStarUI/, writing a #Preview,
  or calling RenderPreview in this repository. SKIP for SwiftStarKit or
  SwiftStarEngine changes that touch no view.
---

# The UI loop

The cycle itself (spec, plan, close) is in `docs/sdd.md`; this skill is the
inner loop for views. Rule from `CLAUDE.md`: a UI change is done only when
each preview it touches has been rendered and looked at, and both test tiers
are green.

## Scheme and paths

- Previews need the **`SwiftStarUI` scheme** active (`XcodeListSchemes`,
  `XcodeSwitchScheme`). `DebugDylibNotEnabled` from `RenderPreview` means the
  executable's scheme is active instead.
- `RenderPreview` takes Xcode project paths, not filesystem paths:
  `swiftstar/Sources/SwiftStarUI/Session/SessionView.swift`. Find the exact
  form with `XcodeGlob` (pattern `**/SwiftStarUI/**/*.swift`).
- `previewDefinitionIndexInFile` counts `#Preview`s from the top, from 0.
  Every preview is named; check the returned `displayName` matches the one
  you meant.
- This is a bare SwiftPM package: `UpdateTargetBuildSetting` and
  `XcodeListTargets` don't work. Change settings in `Package.swift`.

## The gallery: the real window, no engine

`SwiftStarGallery` (its own scheme, SU.12) opens the real window and menus
over the preview fixtures' running controller. It never starts the engine,
so no GPU and no engine lock; its settings are its own defaults domain.
Use it for anything the canvas can't vouch for: the toolbar, the menus,
window chrome, splitters.

1. `XcodeSwitchScheme` to `SwiftStarGallery`, then `RunProject`.
2. `Tools/window-shot.sh SwiftStarGallery /tmp/gallery.png`, then read it.
   It needs Screen Recording for Xcode (granted 2026-10-14).
3. Switch back to `SwiftStarUI` before `RenderPreview`.

Its console fills with CoreUI "unable to find a bundle" faults and `linkd`
connection errors: noise from a bare executable, not failures.

## Layout

`Sources/SwiftStarUI/` is in feature folders: `Session/` (the window's
parts), `Transcript/`, `Inspector/`, `Settings/`, `Shell/`, `Components/`,
`State/` (`EngineController`), `PreviewSupport/`. MV, not MVVM:
`EngineController` is the one `@Observable` app object; leaf views take plain
values. Add a small `@Observable` type only where a view has logic worth
testing.

## Previews and fixtures

- Views that read `EngineController` get it from a trait:
  `#Preview("Running", traits: .runningSession)`. Traits: `.idleSession` and
  `.runningSession` (`PreviewSupport/PreviewTraits.swift`).
  Never `.environment(EngineController.preview…)` directly.
- A trait's controller is shared by reference across previews. A preview
  that mutates it builds its own `EngineController(model:)` in its body.
- Value-taking views use the fixtures in `PreviewSupport/PreviewFixtures.swift`.
- **Previews never start the engine.** Controllers come only from
  `EngineController(model:)`, whose `start()` and `loadCatalogIfNeeded()`
  return early. A preview must never spawn `ds4-dogfood`.
- A preview that needs a stored setting uses `.defaultAppStorage(...)` with
  `PreviewDefaults` (an isolated suite), never the real app's defaults.

## Known limits

- **`RenderPreview` snapshots the first frame.** State changed in `.task` or
  `.onAppear`, timed or not, does not show. Interaction checks (toggles,
  transitions) need the live canvas, which is the owner's to run.
- **`.menuStyle(.borderlessButton)` toolbar menus ignore `.font` and the
  label's `.padding`** (SU.4, SU.6f probes).
- **The canvas lies about toolbars.** With the default menu style, previews
  showed the menus' text with native insets; the running app showed only
  the label's image, so the model and context menus were blank (SU.6f,
  reverted). Check a toolbar change in the gallery (above).
- Snapshot filenames contain a narrow no-break space before AM/PM; copy them
  with a glob, not a typed name.
- To look at many renders at once, tile them into one image (a small AppKit
  script works; there is no ImageMagick here).

## Xcode's tools from terminal Claude Code

Xcode's agent gets the tools as `xcode-tools` automatically. Terminal Claude
Code gets them through the bridge, registered once per clone:

1. In Xcode: Settings > Intelligence > Model Context Protocol, turn on
   "Allow external agents to use Xcode tools", and open this package in Xcode.
2. In a terminal, from the repo: `claude mcp add --transport stdio xcode -- xcrun mcpbridge`
   (local scope: private to you, this project). `claude mcp list` should show
   `xcode` connected. Its tools are named `mcp__xcode__…`.
3. Xcode asks to approve the agent on first connection; choose Always Allow or
   24 hours. `xcrun mcp-server status` shows current grants and expiries.
4. A new terminal agent's first Xcode tool call fails with "This agent isn't
   approved to use Xcode's tools yet. Call XcodeOpenWorkspace…". Call
   `XcodeOpenWorkspace` on the repo first; that triggers the approval.
5. **Check the scheme on every run.** The terminal agent can find a different
   active scheme from the one Xcode's agent left (seen: `SwiftStar-Package`).
   Switch to `SwiftStarUI` before `RenderPreview`.

Verified 2026-10-04: terminal `claude -p` with `--allowedTools "mcp__xcode__*"`
rendered `SessionView`'s "Running" preview with no errors.

Two traps, both checked 2026-10-04:

- **Don't commit a project `.mcp.json` for the bridge.** Xcode's agent honours
  it and then sees every Xcode tool twice (`xcode` and `xcode-tools`).
- **Xcode's agent can't run `claude mcp …` for you as-is.** Its shell inherits
  `CLAUDE_CONFIG_DIR` pointing at Xcode's own agent config, so the command
  would change the wrong config. Use `env -u CLAUDE_CONFIG_DIR claude …`. Even
  then terminal Claude may report "Not logged in" from that shell; run
  terminal checks in your own terminal.

## Tests

- `just test`: fast tier. `just integration`: also runs the integration
  tests, which a plain `swift test` (or Xcode's test tools) skips because
  they are env-gated. Run both through the shell.
- Builds treat warnings as errors on our own targets.

## Committing

Xcode adds new files to git's index on its own. Run `git status` before each
commit and commit only the task's files. Never bypass the pre-commit hook
(`just lint-docs`).
