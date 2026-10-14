# SU.6e: native look, off the toolbar

A small cycle (`docs/sdd.md`): one doc, no spec. It covers SU.6's "Native
look" punch-list item, for the views 7b doesn't touch.

## Decisions

The owner made these on 2026-10-13.

**D1. One tooltip mechanism: `.help`.** `NativeTooltip` goes. If a tooltip
doesn't show when the owner hovers in the running app, the bridge comes
back for that widget.

**D2. Liquid Glass on the composer, field and button.**
- **The field:** `.glassEffect` in a 20 pt rounded rect, replacing the
  hand-drawn text background, clip and stroke.
- **Send and Stop:** `.buttonStyle(.glassProminent)`.
- **Grouping:** both sit in one `GlassEffectContainer`.

**D3. Analyze tints the glass.** While analyzing, the field's glass is
`.regular.tint(.accentColor)`, replacing the 12% accent overlay.

**D4. What touches 7b's files waits.** These become "after 7b" punch-list
bullets, next to the toolbar padding one:
- rows fading under the composer (`safeAreaBar` and
  `scrollEdgeEffectStyle` in `SessionView`)
- a `ToolbarSpacer` between the session and Inspector buttons
  (`SessionToolbar`)

## Facts this rests on

- **`nativeTooltip` has two callers,** `StatusBarView.swift:42` (the
  context ring) and `MemoryStatusView.swift:28` (GPU memory). Each also
  has `.help(tooltip)` on a `.contentShape(Rectangle())`. The repo audit
  flagged the doubling; the P28 deep review (item 18) expected `.help` on
  a content shape to be enough since macOS 14.
- **A preview can't hover,** so `RenderPreview` can't show a tooltip. D1
  needs the owner's check in the app.
- **The composer is drawn by hand** (`ComposerView.swift:27-64`): a
  `.plain` field on `textBackgroundColor`, and a `.plain` button holding a
  28 pt filled-circle symbol.
- **The glass APIs** (Apple docs, checked 2026-10-13):
  `glassEffect(_:in:)` defaults to `.regular` in a capsule;
  `Glass.tint(_:)` and `GlassEffectContainer` exist; `glassProminent` is a
  `PrimitiveButtonStyle`. Apply `glassEffect` after the modifiers that set
  a view's look.
- **`SessionView.swift:20-27`** stacks transcript, composer and status bar
  in a plain `VStack`, so a scroll edge effect needs `SessionView`.

## Tasks

No logic moves, so there are no new unit tests. Each task's check is its
previews (light and dark, and increased contrast for the composer) plus
`just test` and `just integration`.

### Task 1: one tooltip mechanism

**Files:**
- Modify: `Sources/SwiftStarUI/Session/StatusBarView.swift:42`
- Modify: `Sources/SwiftStarUI/Session/MemoryStatusView.swift:28`
- Delete: `Sources/SwiftStarUI/Components/NativeTooltip.swift`

**Steps:**
1. Remove both `.nativeTooltip(tooltip)` calls; keep `.contentShape` and
   `.help`.
2. Delete `NativeTooltip.swift`.
3. Render `StatusBarView`'s "Running", "Idle" and "No GPU metrics" and
   `MemoryStatusView`'s "Half full": unchanged.
4. Owner: hover the context ring and the GPU figures in the running app.

### Task 2: the composer in glass

**Files:**
- Modify: `Sources/SwiftStarUI/Session/ComposerView.swift:25-65`

**Steps:**
1. Wrap the field-and-button `HStack` in a `GlassEffectContainer`.
2. **The field:** drop `.background`, the tint overlay, `.clipShape` and
   the stroke overlay; add
   `.glassEffect(analyzing ? .regular.tint(.accentColor) : .regular, in: .rect(cornerRadius: 20))`
   after the padding.
3. **The button:** an unfilled symbol (`arrow.up`, `stop.fill`) with
   `.buttonStyle(.glassProminent)`, `.buttonBorderShape(.circle)` and
   `.tint(showsStop ? .red : .accentColor)`. Keep the symbol effect, the
   accessibility label and the disabled rule.
4. Render all four previews ("Ready", "Idle", "Analyzing", "Engine not
   found") in light and dark, and "Ready" with increased contrast. The
   placeholder and typed text must stay legible.

### Task 3: close

- `ROADMAP.md`: the "Native look" bullet goes; D4's two bullets join the
  toolbar padding one under an "After 7b" heading in the punch list; the
  SU.6 row lists 6e.
- This plan gains `## Result`.
- `just lint-docs`, `just test`, `just integration`.

## Result

Done 2026-10-13 on `su-ui`, in three commits: Task 1 (`e4eb7e2`), Task 2
(`88287ae`) and this close.

**Suites:** `just test` (75 passed, integration skipped) and
`just integration` (139 and 75 passed, in its two test products), with
no other test run going.

**Previews:** `StatusBarView`'s "Running", "Idle" and "No GPU metrics" and
`MemoryStatusView`'s "Half full" render unchanged. `ComposerView`'s four
previews were rendered in dark; "Ready" and "Analyzing" in light; "Ready"
with increased contrast. The placeholder reads in each.

**Diverged:**
- **The Analyze tint is the accent at 25%, not full strength.** At full
  strength (`.regular.tint(.accentColor)`, D3 as written) the field went
  solid blue and the light-blue placeholder all but vanished. 25% is close
  to the old 12% wash once the glass is under it.
- **The worktree's first build needed the main checkout's dependency
  clones.** GitHub fetches reset and timed out after 10 minutes. Copying
  `.build/repositories` and `.build/checkouts` from the main checkout
  (same `Package.resolved`), then `swift build --skip-update`, worked.

**The owner's check in the running app:**
- **Tooltips: `.help` alone fails on the rings.** Hovering the GPU figures'
  text showed the tooltip; hovering either ring showed none. Per D1, Task 1
  is reverted, so both widgets have `NativeTooltip` and `.help` again. The
  bridge's doc comment records the recheck.
- **Send enabled and the red Stop look right.** No preview shows them: the
  field's text is private `@State` and no fixture runs a turn.
