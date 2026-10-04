# SwiftStar SU.4 design: the Xcode-first UI loop

**Date:** 2026-10-04
**Status:** approved by the owner 2026-10-04, all five §2 recommendations accepted.
**Phase:** SU, cycle SU.4
**Source:** ROADMAP.md's SU.4 row and the brainstorm's handoff brief,
[`2026-10-04-su4-handoff-brief.md`](../research/2026-10-04-su4-handoff-brief.md).
The brief's "Decisions already made" are settled and not restated here; this
spec applies them to the code at `9771038`.
**Written by:** Xcode 27's Claude Agent (Opus 5.5), with the owner.

## Goal

Make Xcode, with its Claude Agent, the place UI work happens. Open a view,
change it, see its preview, keep both test tiers green. Concretely:

1. `SwiftStarUI` is laid out in feature folders.
2. `SessionView` is split into parts that each have their own preview.
3. Previews get their shared fixtures through `PreviewModifier` traits.
4. Both agents have the guidance and tools the loop needs, and "render the
   preview and look at it" is a written rule for every UI change.
5. The project's own targets build under tighter settings.

SU.5 (cleanup, test modernisation) is the loop's first real use. SU.4 does
not do SU.5's work; see the brief's "Out of scope".

## 1. Environment, confirmed 2026-10-04

Checked by the Xcode agent before writing this spec.

| Check | Result |
|---|---|
| Active scheme | `SwiftStarUI` (four schemes: `SwiftStarUI`, `SwiftStar-Package`, `SwiftStarKit`, `SwiftStar`) |
| `RenderPreview` on `swiftstar/Sources/SwiftStarUI/SessionView.swift` | Renders the running-session fixture on macOS 27.0.1, no errors. Offers Color Scheme, Contrast and Control Borders variants. |
| `just test` | 143 fast tests pass; the 30 integration tests skip without the gate, as expected |
| Project `.claude/skills/` load in Xcode's agent | **Yes, in a fresh session.** A probe skill created mid-session was not visible to the already-running session. A fresh session launched with Xcode's own recipe (`xcrun mcpbridge run-agent claude -p …`) found and ran it. The probe is removed. |
| Xcode stages new files | Creating the probe file added it to the git index without a `git add`. Plan tasks must check `git status` before each commit. |

So a project skill works for both agents, after a session restart. That
settles the brief's open question 2 and makes option (a) of question 1
practical.

## 2. Decisions

Each was put to the owner with a recommendation. The owner accepted all five
on 2026-10-04, so each "Recommended" below is now the decision.

**D1. Which agent drives a cycle?** *Recommended: (a), the Xcode agent drives
SU.4 end to end, without installing superpowers.* `docs/sdd.md` already
overrides the writing-plans skill, and `CLAUDE.md` states the close rule, so
the cycle can be followed from those two files directly. Review uses the
built-in `/code-review` skill, which both agents have. At SU.4's close the
plan's `## Result` records whether this held up, and SU.5 picks its driver
from that evidence. If it doesn't hold up, fall back to (b). Terminal Claude
Code still gets the Xcode tools (§3.5), so either agent can run the loop.

**D2. Keep the macOS 26 floor?** *Recommended: keep it.* The only gain from
macOS 27 is `#Preview(arguments:)` grids. Named previews cover the same
states at a cost of a few more lines.

**D3. Give `MarkdownText` its own module?** *Recommended: no.* Preview builds
compile the whole `SwiftStarUI` target with its dependencies, and Xcode
caches the built `MarkdownView`. `SessionView` and the transcript need
`MarkdownText` anyway. A `SwiftStarMarkdown` target would speed up only the
leaf components' first preview build, at the cost of a fifth target and more
`public` API. Revisit if preview builds are measurably slow.

**D4. Which upcoming features?** *Recommended, on every target this package
defines (tests included):* `NonisolatedNonsendingByDefault` and
`InferIsolatedConformances` (the pair Xcode calls Approachable Concurrency),
and `MemberImportVisibility`. *Deferred:* `InternalImportsByDefault` and
`ExistentialAny` (churn without a behaviour gain now) and strict memory
safety (worth a look for `SwiftStarEngine` alone, later).

**D5. Warnings as errors?** *Recommended: yes, `.treatAllWarnings(as: .error)`
on the package's own targets only, never on dependencies.* The fresh build
has zero warnings today, so this costs nothing now and keeps it that way.
Tools version stays 6.2; that API arrived in 6.2.

## 3. Design

### 3.1 Feature folders

Folders inside `Sources/SwiftStarUI/`; the target list in `Package.swift`
doesn't change. Moves are `git mv` so history follows.

| Folder | Contents |
|---|---|
| `Session/` | `SessionView` (composition only), `SessionToolbar`, `TranscriptView`, `TranscriptRowView`, `ComposerView`, `StatusBarView`, `MemoryStatusView` |
| `Transcript/` | `PromptBubble`, `ThinkingDisclosure` (out of `PromptBubble.swift` into its own file), `ToolCardView`, `MarkdownText` |
| `Inspector/` | `InspectorView` |
| `Settings/` | `SettingsView` |
| `Shell/` | `MainView` |
| `Components/` | `ValueGaugeView`, `NativeTooltip` (out of `SessionView.swift`), `TranscriptFontSize` |
| `State/` | `EngineController` |
| `PreviewSupport/` | `PreviewFixtures`, `PreviewTraits` |

Changes from the brief's proposal: `MainView` gets a `Shell/` folder, since
it fits none of the others. `Severity.color` stays in `ValueGaugeView.swift`;
that misplacement is SU.5's (audit §1f).

### 3.2 Splitting `SessionView`

The audit counted eight jobs in 453 lines. After the split, each part is a
type with its own `#Preview`:

- **`SessionView`** keeps composition, the three `.task`s, and the two
  alerts with their state. It owns nothing else.
- **`SessionToolbar: ToolbarContent`** holds the three menus, the session
  button and the inspector toggle. It takes bindings for the two alert flags
  and the inspector flag. Its preview is a host view with the toolbar
  attached.
- **`TranscriptView`** and **`TranscriptRowView`** take plain values: the
  rows, the pending flags and the workspace URL. They don't read the
  controller.
- **`ComposerView`** reads the controller from the environment, because it
  sends and stops. It owns the input text and focus state.
- **`StatusBarView`** takes plain values: the phase, the composer label and
  the metrics. **`MemoryStatusView`** takes non-optional allocated and budget
  bytes.

Label and button logic moves with its view but isn't extracted or tested
here; SU.5 owns that (audit §1f, §2).

**The memory widget.** SU.3's Backlog entry says this split reopens the
`DebugReplaceableViewStorage` crash question. `StatusBarView` gets a preview
with an `@Previewable` toggle that adds and removes GPU metrics. If that
crashes the live preview, the plan's task fixes the view's shape there. If it
doesn't, the Backlog entry is updated to say so; the Debug-run half stays
open.

**The font size.** The brief allows fixing this bug here if the split moves
the reads, and it does. Today `SessionView` sets `transcriptFontSize` on its
own body and reads it from its parent, so the toolbar, system and error rows,
notice and status bar ignore the slider (audit §1e). Once those reads live in
child views below the modifier, they see the slider's value. A preview at a
non-default size shows it. The spec records the fix as a side effect of the
split, not as SU.5's item.

### 3.3 Shared fixtures through `PreviewModifier`

- `PreviewSupport/PreviewTraits.swift` defines one `PreviewModifier` per
  controller fixture: idle, running, and the states the split needs (for
  example running without GPU metrics). Each one's `makeSharedContext`
  returns an `EngineController(model:)` fixture, and its `body` applies
  `.environment(context)`.
- `PreviewTrait` gets a static member for each: `.idleSession`,
  `.runningSession`, and so on. Call sites read
  `#Preview("Running", traits: .runningSession)`.
- Leaf views that take plain values use no trait. They take values straight
  from the fixtures in `PreviewFixtures.swift`.
- Every `#Preview` gets a name, so an index passed to `RenderPreview` can be
  checked against the name it returns.
- The shared context is cached and shared by reference. A preview that
  mutates the controller, such as typing into the composer and pressing send,
  builds its own fixture in the preview body instead of using the trait.
- Fixtures still never touch the engine. `EngineController(model:)` keeps
  `isFixture`, and nothing in `PreviewSupport/` calls `start()`.

### 3.4 The loop's guidance

- **`CLAUDE.md`** gains a short "UI work" section. A UI change isn't done
  until each preview it affects has been rendered with `RenderPreview` and
  looked at. Both test tiers stay green. The section points at the skill for
  the details.
- **`.claude/skills/ui-loop/SKILL.md`** is a project skill both agents load.
  It covers:
  - the scheme to use and the `DebugDylibNotEnabled` symptom;
  - the `RenderPreview` path form and preview indexes;
  - the fixture rule;
  - `just test` and `just integration`, and that the integration gate needs
    the shell;
  - that build-setting tools don't work on a bare package;
  - that Xcode stages new files on its own.

  The skill points at `docs/sdd.md` rather than restating it.

### 3.5 Xcode tools for terminal Claude Code

Register the bridge for terminal Claude Code at user scope, and document the
command, the Xcode setting to enable and the approval prompt in the skill:

```
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

No committed `.mcp.json`. Xcode's agent already gets `xcode-tools` injected.
Whether it also honours a project `.mcp.json`, and would then see the tools
twice, is unconfirmed (Xcode research §2). The plan includes one check of
that. If the check shows no duplication, a committed `.mcp.json` can follow.
Running `claude mcp add` changes the owner's own config, so the owner runs
it, or approves it explicitly.

### 3.6 Build settings

`Package.swift` gains one shared settings array that every target uses: the
language mode, D4's three features and D5's warnings rule. `defaultIsolation`
stays on the targets that have it now. Risk: under
`NonisolatedNonsendingByDefault`, nonisolated async code runs on the caller's
actor. The engine loader's one async entry point already moves its blocking
work onto GCD, so the risk is low. The integration tier, run through
`just integration`, is the check. If a feature changes behaviour in
`SwiftStarEngine`, that target opts out and the spec records why.

### 3.7 Tests

No test changes are planned. Tests import modules rather than source paths,
so moving files doesn't touch them. Both tiers run after each task. The
untested `start()` refusal in SU.3's Backlog stays there:
`EngineController` is moved, not edited.

## 4. Done when

- Every file in `SwiftStarUI` sits in the folder §3.1 gives it, and
  `SessionView.swift` holds composition only.
- Every view in §3.1 has at least one named `#Preview`, and each one has been
  rendered with `RenderPreview` and looked at during the cycle. That includes
  the memory-toggle and font-size previews.
- Previews that need a controller use a `PreviewTrait`; no preview calls
  `.environment(EngineController.preview…)` directly.
- `CLAUDE.md` has the UI-work rule. The `ui-loop` skill exists and a fresh
  session loads it.
- Terminal Claude Code can call `RenderPreview`, or the plan's `## Result`
  says why not.
- `Package.swift` applies §3.6 and the build has zero warnings.
- `just test` and `just integration` are green, and `just lint-docs` passes.
- The ROADMAP SU.4 row and `## Now` are updated, and the SU.3 Backlog entry
  reflects what the memory-toggle preview showed.

## 5. Risks

- **Preview indexes shift** as previews are added. Naming every preview
  (§3.3) lets each render be checked against the name it returns.
- **The toolbar preview** may not render toolbar items in a canvas host. If
  it doesn't, `SessionView`'s own preview covers the toolbar, and the plan
  says so.
- **Warnings as errors** could block the loop if the Xcode 27 toolchain adds
  a new warning. The escape hatch is `.treatWarning(_:as: .warning)` for that
  one group, recorded in the plan.
