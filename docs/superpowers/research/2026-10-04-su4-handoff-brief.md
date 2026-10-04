# SU.4 handoff brief: the Xcode-first UI loop

> For Claude Agent running inside Xcode 27, picking up SU.4 from a brainstorm
> held in terminal Claude Code on 2026-10-04. The brainstorm settled the
> direction and the decisions below; the spec, plan and implementation are
> yours, with the human working alongside you in Xcode.

## Why this cycle exists

The owner wants to work like this from now on: sit in Xcode with you, open a
SwiftUI view, change it, see the preview update immediately, and iterate fast
on the UI without the engine. Unit and integration tests stay current as the
UI changes. SU.4 builds that loop. SU.5 (cleanup and test modernisation)
comes next and will be done *inside* this loop, so SU.4 should not try to do
SU.5's work.

## Read first

1. `CLAUDE.md`: repo rules, including how a cycle closes.
2. `docs/sdd.md`: the cycle (brainstorm → spec → plan → execute →
   review/close), the local plan rule (files, interfaces and proving test per
   task; no pasted bodies; under 400 lines, under 25% fenced), and the
   ROADMAP cell caps.
3. `BRIEF.md`, "Targets": the four targets and why `SwiftStarUI` is a
   library.
4. `ROADMAP.md`: the SU rows and the Backlog entry "SU.3's deferred items".
5. The research behind this brief, all in `docs/superpowers/research/`:
   - `2026-10-04-swiftui-layout-previews-testing.md`: current SwiftUI
     layout, previews, Swift Testing and build-settings practice.
   - `2026-10-04-xcode-27-claude-agent.md`: how you are configured, which
     tools you have, and what is confirmed and what isn't.
   - `2026-10-04-repo-audit.md`: the state of the code at `fb46abb`.
6. The SU.3 spec and plan
   (`docs/superpowers/{specs,plans}/2026-10-03-su3-preview-adoption*.md`):
   how previews and fixtures got where they are.

## Environment facts

- **Bare SwiftPM package, no `.xcodeproj`.** Targets are `SwiftStarKit` (pure
  logic), `SwiftStarEngine` (subprocess I/O), `SwiftStarUI` (views,
  `EngineController`, `PreviewFixtures`) and `SwiftStar` (`@main` only).
- **Previews need the `SwiftStarUI` scheme active.** The executable target
  can't be previewed (`ENABLE_DEBUG_DYLIB`), and Xcode creates package
  schemes only per product. If `RenderPreview` reports `DebugDylibNotEnabled`,
  the wrong scheme is active.
- **`RenderPreview` paths are project-organization paths, not filesystem
  paths.** In SU.3, `SwiftStar/Sources/SwiftStarUI/SessionView.swift` worked.
  Use `XcodeGlob` to find the exact form. `previewDefinitionIndexInFile`
  picks among several previews in one file.
- **Build-setting tools don't work on a bare package.**
  `UpdateTargetBuildSetting` and `XcodeListTargets` fail or return nothing.
  Change settings in `Package.swift`.
- **Tests:** `just test` runs the fast tier. `just integration` runs the
  integration tier, which is env-gated: a plain `swift test` skips those 30
  tests. Run them through the shell. Xcode's test tools may not set the gate.
- **Fixtures never touch the engine.** Controllers built with
  `EngineController(model:)` set `isFixture`, so `start()` and
  `loadCatalogIfNeeded()` return early. Keep it that way: a preview must
  never spawn `ds4-dogfood`.
- **Your setup is not the owner's terminal setup.** You read the repo's
  `CLAUDE.md`, but not `~/.claude`. The superpowers skills the repo's docs
  name (writing-plans, subagent-driven-development,
  finishing-a-development-branch) are not installed for you. Follow the
  steps `docs/sdd.md` and `CLAUDE.md` describe directly.
- **Commits:** small, one per task. End each message with a
  `Co-Authored-By:` trailer naming the model you are running as. A
  pre-commit hook runs `just lint-docs`; never bypass it.

## Decisions already made in the brainstorm

- **SU.4 comes before cleanup.** The owner chose this order so the cleanup
  becomes the loop's first real use.
- **MV, not MVVM.** `EngineController` stays the single `@Observable` app
  object. Leaf views take plain values. Add a small `@Observable` type only
  where a view has logic worth testing; don't add a `ViewModels/` layer.
- **Feature folders inside `SwiftStarUI`.** The four targets stay the layer
  split. A starting proposal for the spec to confirm or change:
  - `Session/`: `SessionView` split into its toolbar and menus, transcript,
    composer, and status bar.
  - `Transcript/`: `PromptBubble`, `ThinkingDisclosure`, `ToolCardView`,
    `MarkdownText`.
  - `Inspector/` and `Settings/`.
  - `Components/`: `ValueGaugeView`, the native tooltip bridge,
    `TranscriptFontSize`.
  - `State/`: `EngineController`.
  - `PreviewSupport/`: fixtures and preview modifiers.

  The audit found `SessionView` (453 lines) doing eight jobs; splitting it is
  what makes each part previewable.
- **Previews use `PreviewModifier`.** Shared fixtures come through
  `PreviewModifier` with a named `PreviewTrait`, for example
  `#Preview(traits: .runningSession)`, instead of repeating
  `.environment(EngineController.previewRunning)`. Remember that the shared
  context is shared by reference.
- **`RenderPreview` before "done".** A UI change isn't finished until its
  preview has been rendered and looked at. This is the old SU.4 house rule,
  now part of this cycle. Write it into `CLAUDE.md` or a project skill.
- **Tooling for both agents.**
  - Wire Xcode's MCP tools for terminal Claude Code too
    (`claude mcp add --transport stdio xcode -- xcrun mcpbridge`; see the
    Xcode research doc, §4, for the scope and approval flow).
  - Give the loop the project-level guidance it needs: preview, scheme,
    fixtures, test commands.
- **Build settings get tightened.** Candidates are in the layout research,
  §4.3: the approachable-concurrency features, `MemberImportVisibility` and
  warnings as errors for the project's own targets. The spec picks which.

## Open questions for the human, to settle in the spec

1. **Which agent drives a cycle?** Options:
   - (a) you drive the whole cycle in Xcode, which needs the SDD process
     available to you: superpowers installed into Xcode's
     `ClaudeAgentConfig`, or project skills that encode `docs/sdd.md`;
   - (b) terminal Claude Code runs specs, plans, reviews and closing, and
     you run the edit → preview → test loop;
   - (c) start with (b) and add a time-boxed check of whether (a) works.
2. **Do project-level `.claude/skills` load for you?** This is inferred but
   unconfirmed: a project command was seen in an earlier Xcode session.
   Check it first with a throwaway skill before building on it.
3. **Keep the macOS 26 floor?** `#Preview(arguments:)` grids need macOS 27.
   Below that, use named previews or a `ForEach`.
4. **Give `MarkdownText` its own module?** `MarkdownView` is the heavy
   dependency. A small `SwiftStarMarkdown` target would keep it out of other
   views' preview builds, at the cost of one more target.
5. **Which upcoming features, and warnings as errors?** See the layout
   research, §4.3 and §4.5.

## Out of scope for SU.4 (SU.5 owns these)

- **Dead code and stale docs** from the audit's §1, including the
  `FastTierGuard` references.
- **The two suspected UI bugs:** the font-size environment scope and the
  Quick Look path. Exception: if splitting `SessionView` moves the
  font-size read anyway, fix it there and say so.
- **Extracting and testing `SessionView`'s label and button logic,** and
  adopting newer Swift Testing features. SU.4 keeps the existing tests green
  and moves them as files move, but doesn't modernise them.
- **ROADMAP reorganisation.**

## Suggested first steps

1. Confirm the environment: `SwiftStarUI` scheme active, `RenderPreview` on
   `SessionView` returns an image, `just test` passes.
2. Answer open question 2 with a throwaway project skill, then remove it.
3. Draft the spec at
   `docs/superpowers/specs/<date>-su4-xcode-first-ui-loop-design.md`, settle
   the open questions with the human, and get the spec approved.
4. Write the plan under the local plan rule, get it approved, and execute
   it task by task. For every view task, render and look at its previews;
   keep both test tiers green.
5. Close per `CLAUDE.md`: update the SU.4 row and `## Now`, add the plan's
   `## Result`, and pass `just lint-docs`.
