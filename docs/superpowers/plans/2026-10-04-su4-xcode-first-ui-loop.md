---
phase: SU
cycle: SU.4
lifecycle: closed
---

# SU.4 Xcode-first UI loop implementation plan

> **Driver:** Xcode 27's Claude Agent, end to end (spec decision D1). No
> superpowers skills; the cycle follows `docs/sdd.md` and `CLAUDE.md`.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** `SwiftStarUI` in feature folders, `SessionView` split into
previewable parts, shared fixtures through `PreviewModifier` traits, the
loop's guidance written down for both agents, and tighter build settings.

**Spec:** `docs/superpowers/specs/2026-10-04-su4-xcode-first-ui-loop-design.md`
(approved 2026-10-04, decisions D1–D5 accepted).

**Branch:** `su4-xcode-first-ui-loop`, off `main` at `9771038`.

## Global constraints

- After each task: `swift build` has zero warnings, `just test` and
  `just integration` are green.
- A view task is done only when every preview it adds or touches has been
  rendered with `RenderPreview` and looked at. The task's commit message
  names the previews rendered.
- Every `#Preview` is named. A render is checked against the
  `displayName` that `RenderPreview` returns, not just its index.
- Xcode stages new files on its own. Run `git status` before each commit and
  commit only the task's files.
- One commit per task, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never bypass
  the pre-commit hook.
- Previews never start the engine: controller fixtures come from
  `EngineController(model:)` only.

## Review focus

1. **Moves are moves.** Tasks 2, 4 and 5 change no behaviour except the
   font-size scope fix. Diff review checks that each moved body is
   unchanged apart from access control and the parameters it now receives.
2. **Leaf views take values.** `TranscriptView`, `TranscriptRowView`,
   `StatusBarView` and `MemoryStatusView` don't read `EngineController`.
3. **No preview writes the real app's defaults.** Previews that need a font
   size use their own `UserDefaults` suite.

---

### Task 1: Build settings

**Files:**
- Modify: `Package.swift:26-62` (all six targets)

**Interfaces (produces):** one shared settings array, applied to every
target. It holds the Swift 6 language mode, the upcoming features
`NonisolatedNonsendingByDefault`, `InferIsolatedConformances` and
`MemberImportVisibility`, and `.treatAllWarnings(as: .error)`.
`.defaultIsolation(MainActor.self)` stays on `SwiftStarUI`, `SwiftStar`
and `SwiftStarIntegrationTests` only.

**Proves it:**
- `swift build`: zero warnings and zero errors. Fix any new diagnostic in
  the source. If a feature changes behaviour in `SwiftStarEngine`, that
  target opts out and the commit says why (spec §3.6).
- `just test`: 143 pass. `just integration`: 30 pass with the gate set.
- Show the rule bites: add an unused local variable to one `SwiftStarUI`
  file, confirm `swift build` fails with an error rather than a warning,
  then remove it.
- `RenderPreview` on `SessionView` still renders.

- [x] **Step 1:** implement, verify as above, commit.

---

### Task 2: Feature folders

**Files:** `git mv` within `Sources/SwiftStarUI/`, following spec §3.1:
- `Session/SessionView.swift`
- `Transcript/PromptBubble.swift`, `Transcript/ToolCardView.swift`,
  `Transcript/MarkdownText.swift`
- New: `Transcript/ThinkingDisclosure.swift`, with the type and its preview
  moved out of `PromptBubble.swift:33-65` and `:79-83`
- `Inspector/InspectorView.swift`, `Settings/SettingsView.swift`,
  `Shell/MainView.swift`
- `Components/ValueGaugeView.swift`, `Components/TranscriptFontSize.swift`
- New: `Components/NativeTooltip.swift`, with `NativeTooltipView`,
  `NativeTooltipModifier` and `nativeTooltip(_:)` moved out of
  `SessionView.swift:415-448`
- `State/EngineController.swift`
- `PreviewSupport/PreviewFixtures.swift`

**Interfaces (produces):** `extension View { func nativeTooltip(_ text:
String) -> some View }`, now internal rather than private. No other
signature changes.

**Proves it:**
- `swift build` clean, and both tiers green.
- `XcodeGlob` shows the new paths in Xcode's file tree.
- `RenderPreview` renders every existing preview at its new path: 14
  previews across `SessionView`, `MainView`, `InspectorView`,
  `SettingsView`, `PromptBubble` (2), `ThinkingDisclosure`, `ToolCardView`
  (3), `MarkdownText` and `ValueGaugeView` (3).
- `git log --follow` on one moved file shows its history.

- [x] **Step 1:** move, verify, commit.

---

### Task 3: `PreviewModifier` traits

**Files:**
- New: `PreviewSupport/PreviewTraits.swift`
- Modify: `PreviewSupport/PreviewFixtures.swift`, adding a running fixture
  without GPU metrics and a metrics value for the status bar
- Modify: the previews in `Session/SessionView.swift`,
  `Shell/MainView.swift` and `Inspector/InspectorView.swift`, which move to
  traits; name the previews in `SessionView`, `MainView`, `InspectorView`,
  `SettingsView` and `MarkdownText`

**Interfaces (produces):**

```swift
struct IdleSessionPreview: PreviewModifier      // context: EngineController
struct RunningSessionPreview: PreviewModifier
struct RunningNoGPUSessionPreview: PreviewModifier
extension PreviewTrait where T == Preview.ViewTraits {
    static var idleSession: Self { get }
    static var runningSession: Self { get }
    static var runningSessionNoGPU: Self { get }
}
extension EngineController { static var previewRunningNoGPU: EngineController { get } }
extension EngineMetricsState { static var previewRunning: EngineMetricsState { get } }
```

**Proves it:**
- `grep -rn "environment(EngineController.preview" Sources/` finds
  nothing.
- `RenderPreview` renders each preview that now uses a trait, under its
  name, and shows the fixture's state. `MainView` and `InspectorView` show
  the running session; `SessionView` gets an "Idle" preview too.
- Both tiers green.

- [x] **Step 1:** implement, verify, commit.

---

### Task 4: Transcript and status bar out of `SessionView`

**Files:**
- New: `Session/TranscriptView.swift` and `Session/TranscriptRowView.swift`,
  with the bodies of `SessionView.swift:201-254` moved
- New: `Session/StatusBarView.swift` and `Session/MemoryStatusView.swift`,
  with the bodies of `SessionView.swift:345-412` moved
- Modify: `Session/SessionView.swift`, which now composes these views

**Interfaces (produces):**

```swift
struct TranscriptView: View { init(transcript: EngineTranscript, workspace: URL?) }
struct TranscriptRowView: View { init(row: TranscriptRow, queued: Bool, workspace: URL?) }
struct StatusBarView: View {
    init(phase: EngineSessionPhase, composerLabel: String, metrics: EngineMetricsState)
}
struct MemoryStatusView: View { init(allocatedBytes: Int64, budgetBytes: Int64) }
```

`TranscriptRowView` and `StatusBarView` read `\.transcriptFontSize` from
their own environment. That is the font-size fix for these rows (spec §3.2).

**Previews, each rendered:**
- `TranscriptView` "Running" and "Empty", built from the fixtures'
  transcripts.
- `TranscriptRowView` "System", "Error" and "Answer with summary".
- `StatusBarView` "Running", "Idle" and "No GPU metrics".
- `StatusBarView` "GPU toggle": an `@Previewable` toggle that adds and
  removes GPU metrics. Run it live in the canvas and flip the toggle both
  ways. **If it crashes**, change `MemoryStatusView`'s shape in this task
  until it doesn't, and record the shape in `## Result`. **If it doesn't
  crash**, record that for the Backlog update in Task 8.
- `MemoryStatusView` "Half full".
- `SessionView` "Running", which must still match its Task 3 render.

**Proves it:**
- `TranscriptView.swift`, `TranscriptRowView.swift`, `StatusBarView.swift`
  and `MemoryStatusView.swift` contain no `EngineController`; grep confirms
  it.
- Both tiers green.

- [x] **Step 1:** implement, render and look, commit.

---

### Task 5: Composer and toolbar out of `SessionView`

**Files:**
- New: `Session/ComposerView.swift`, with `SessionView.swift:256-343`
  moved: the composer, notice text, send, trimmed input, input and focus
  state
- New: `Session/SessionToolbar.swift`, with `SessionView.swift:28-56` and
  `:80-199` moved: the menus, menu helpers, session-action labels and
  `pickWorkspace`
- Modify: `Session/SessionView.swift`, which keeps composition, the three
  `.task`s, the two alerts and their state (`:57-77`), and the
  `transcriptFontSize` environment modifier. The `envTranscriptFontSize`
  property is deleted.

**Interfaces (produces):**

```swift
struct ComposerView: View { init() }   // reads EngineController from the environment
struct SessionToolbar: ToolbarContent {
    init(askingModel: Binding<Bool>, askingContext: Binding<Bool>,
         entry: Binding<String>, inspectorPresented: Binding<Bool>)
}
```

**The font-size check.** The fix proves itself with a before and after
render. Before the split, at the start of this task, render `SessionView`
with a preview whose isolated `UserDefaults` suite sets
`transcriptFontSize` to the largest slot. Save the image: the status bar,
the system and error rows and the toolbar menus are at 16 pt. After the
split, render the same preview again. Those parts now follow the larger
size. That preview, "Large font", stays in the file. If the toolbar menus
still don't follow, give `SessionToolbar` its own environment read, and say
so in `## Result`.

**Previews, each rendered:**
- `ComposerView` "Ready" (`.runningSession`), "Idle" (`.idleSession`), and
  "Engine not found" (its own fixture, built in the preview body).
- `SessionToolbar` "Running", a host view with the toolbar attached. If the
  canvas doesn't draw toolbar items, record that, and let `SessionView`'s
  previews cover the toolbar (spec §5).
- `SessionView` "Running", "Idle" and "Large font".

**Proves it:**
- `SessionView.swift` holds composition only; it should end up well under
  100 lines.
- Both tiers green.

- [x] **Step 1:** render the "Large font" before-image, implement, render
  and look, commit.

---

### Task 6: The loop's guidance

**Files:**
- Modify: `CLAUDE.md`, adding a short "UI work" section with the
  render-before-done rule, both test tiers, and a pointer to the skill
- New: `.claude/skills/ui-loop/SKILL.md`, with the contents spec §3.4
  lists. Its `description` says when to use it: any change to a file under
  `Sources/SwiftStarUI/`.

**Proves it:**
- A fresh Xcode-configured session loads the skill. Run
  `xcrun mcpbridge run-agent claude --model haiku -p "<ask it to name the
  scheme previews need, from the ui-loop skill>"` and check that it answers
  `SwiftStarUI` and names the skill.
- `just lint-docs` green.

- [x] **Step 1:** write, verify, commit.

---

### Task 7: Xcode tools for terminal Claude Code

**Owner step.** The owner runs the command below, or approves it when the
agent runs it. It writes the owner's user-scope Claude Code config.

```
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

**Files:**
- Modify: `.claude/skills/ui-loop/SKILL.md`, adding the registration
  command, the Xcode setting to enable ("Allow external agents to use
  Xcode tools"), the approval prompt, and `xcrun mcp-server status`

**Proves it:**
- `claude mcp list` shows `xcode` connected.
- Terminal `claude -p` renders `Session/SessionView.swift` "Running"
  through `RenderPreview`, and returns a snapshot path.
- **The duplication check (spec §3.5).** Write a throwaway project
  `.mcp.json` that registers the bridge. Start a fresh Xcode-configured
  session and ask it to list its MCP servers. Record whether Xcode tools
  appear once or twice, then delete the file. Record the result in the
  skill and in `## Result`.

- [x] **Step 1:** owner registers the bridge, then verify, record and commit.

---

### Task 8: Review and close

- Run `/code-review` over the branch diff, checking the review focus above,
  and fix what it confirms.
- `ROADMAP.md`: update the SU.4 Status cell and `## Now` (SU.5 is next).
  Update the Backlog entry "SU.3's deferred items" with Task 4's GPU-toggle
  result. The status bar split happened, so that reopen condition has been
  met.
- This plan: set `lifecycle: closed` and add `## Result`. The Result covers
  the commits, what diverged, what was descoped, and D1's verdict: did
  driving the whole cycle from Xcode hold up, and what should SU.5 use?
  Replace any fence over 15 lines with a `path:line` reference.
- `just lint-docs` green. Then offer the finish options: merge to `main`,
  open a PR, or keep the branch.

- [x] **Step 1:** review, close, verify, commit.

## Result

Closed 2026-10-04 on branch `su4-xcode-first-ui-loop`.

**Commits:** spec `e814143`, plan `807d4a3`, Task 1 `1077bdf`, Task 2
`de037c4`, Task 3 `dfdd0cc`, Task 4 `11d8fb1`, Task 5 `70c3b80`, Task 6
`950949e`, Task 7 `945fedf`, close (this commit). Fast tier 143 and
integration tier 30 green after every task.

**What shipped:** `Package.swift:1-20` (shared settings);
`Sources/SwiftStarUI/` in eight feature folders; `Session/` holds
`SessionView` (64 lines, from 453), `SessionToolbar`, `TranscriptView`,
`TranscriptRowView`, `ComposerView`, `StatusBarView`, `MemoryStatusView`;
`PreviewSupport/PreviewTraits.swift`; the `CLAUDE.md` "UI work" section;
`.claude/skills/ui-loop/SKILL.md`.

**What diverged:**
- Task 1: the new settings surfaced two real diagnostics, both fixed in
  source. `EngineSession`'s `ChunkBytes` iterator now calls
  `next(isolation: #isolation)`. `MetricsFormattingTests` was missing
  `import Foundation`.
- Task 4: `RenderPreview` snapshots the first frame only, so it can't flip
  the GPU toggle. Timed flips and run-loop flips both read "0 of 6". The
  check moved to the owner's live canvas.
- Task 5: the input-focus `.task` moved into `ComposerView` with the focus
  state, so `SessionView` keeps two tasks, not three. The font modifier now
  sits after `.toolbar`. A probe showed toolbar menus ignore `.font` (30 pt
  rendered unchanged), so the toolbar half of the font bug can't be fixed
  through font size. The before-image was taken after Task 4, so it
  contrasts only the toolbar.
- Task 7: the bridge was already registered for terminal Claude Code. A
  throwaway project `.mcp.json` made Xcode's agent list `xcode` and
  `xcode-tools` side by side, so none is committed. A terminal render could
  not run from Xcode's shell: it inherits Xcode's `CLAUDE_CONFIG_DIR`, and
  terminal Claude reports "Not logged in" there.
- Task 8: `/code-review` at medium found nothing.

**Descoped or owed:**
- Owner, live canvas: open `StatusBarView`'s "GPU toggle" preview and see
  "6 of 6" with no crash.
- Owner, terminal: run `claude -p` asking for `RenderPreview` on
  `swiftstar/Sources/SwiftStarUI/Session/SessionView.swift`.
- Owner, live app: the session button and menus update when the phase
  changes. They now read the controller inside `SessionToolbar`
  (`ToolbarContent`), which a first-frame snapshot can't exercise.

**D1 verdict: it held up.** Xcode's agent ran spec, plan, eight tasks,
review and close without superpowers, from `docs/sdd.md` and `CLAUDE.md`
alone. Friction came from the tools, not the process:
- the shell's permission hook timed out several times;
- `RenderPreview` sees only the first frame;
- snapshot filenames carry a narrow no-break space;
- there was no image-tiling tool, so a scratch AppKit script stood in.

Project skills load in a fresh session, and the `ui-loop` skill also appeared
in this running session after a delay. Recommendation: SU.5 runs the same
way, in Xcode.

