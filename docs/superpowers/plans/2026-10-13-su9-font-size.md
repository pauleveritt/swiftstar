# SU.9: font size

A small cycle (`docs/sdd.md`): one doc, no spec. The owner found the text
too small at the default.

## Decisions

The owner made D1 to D3 on 2026-10-13; D4 follows from them.

**D1. One setting scales every text in the window:** transcript,
composer, sidebar, inspector, status bar, tool cards and banners. The
fixed `.caption`-style sizes become sizes relative to the setting.

**D2. Five sizes, the middle the default:** 14, 16, **18**, 20, 24 pt.

**D3. ⌘+ and ⌘− wait for 7b.** View › Bigger, Smaller and Actual Size
belong in `SwiftStarApp`'s commands, which 7b is rewriting. They become an
"after 7b" bullet.

**D4. A new saved key, `fontSize`.** The packaged app has
`transcriptFontSize = 16` saved, and 16 is still a size, so the old key
would hold the owner below the new default. Starting from a new key, every
install opens at 18 once.

## Facts this rests on

- **Today's scale** (`TranscriptFontScale.swift`): 12, 14, 16, 20; default
  16, the third slot. Settings has its slider; `SessionView` puts the size
  in the environment as `transcriptFontSize`.
- **The environment covers only `SessionView`'s subtree** (`:36`).
  `MainView` holds the sidebar and the inspector outside it
  (`Shell/MainView.swift:13-24`). 7b only renders `MainView`'s preview; it
  doesn't change it.
- **The fixed sizes:**
  - `ConversationList.swift:25` (`.caption`)
  - `InspectorView.swift:13,19,31,48,55,71` (`.headline`, `.caption`,
    monospaced `.body`)
  - `ToolCardView.swift:22,29,35,39` (`.caption`, monospaced `.caption`,
    `.caption2`)
  - `TranscriptRowView.swift:40,48,92,100` (`.caption2`, `.caption`)
  - `MemoryStatusView.swift:18` (`.caption2`)
- **Not in scope:**
  - toolbar menus ignore `.font` (ui-loop's known limits)
  - Settings is its own window, and stays system-sized
  - `SessionView` is 7b's, but needs no change: it reads the key through
    `DefaultsKey`

## Tasks

### Task 1: the scale in Kit

**Files:**
- Modify: `Sources/SwiftStarKit/TranscriptFontScale.swift`
- Modify: `Sources/SwiftStarKit/DefaultsKey.swift` (raw value `fontSize`)
- Tests: `Tests/SwiftStarKitTests/TranscriptFontScaleTests.swift`,
  `Tests/SwiftStarKitTests/DefaultsKeyTests.swift`

**Interfaces:**
- `sizes = [14, 16, 18, 20, 24]`, `defaultSize = 18`; the clamp rule is
  unchanged (nearest, ties to the smaller).
- `public enum TextRole { case headline, caption, caption2 }`, and
  `TranscriptFontScale.points(_ role: TextRole, base: Double) -> Double`:
  headline = base, caption = base × 0.8, caption2 = base × 0.72. These are
  close to macOS's own ratios to its 13 pt body.

**Tests first:** the new sizes and default; the clamp table redone for
them; `points` at 18 and at 14; the raw value `fontSize`.

### Task 2: every text follows it

**Files:**
- Modify: `Sources/SwiftStarUI/Components/TranscriptFontSize.swift`: a
  `Font` helper, `.scaled(_ role:, base:, design:)`, over `points`
- Modify: `Sources/SwiftStarUI/Shell/MainView.swift`: puts the size in the
  environment, so the sidebar and the inspector get it
- Modify: the fixed sizes listed above, which move to the helper
- Modify: `Sources/SwiftStarUI/Settings/SettingsView.swift`: the label
  reads "Font size"

**Steps:**
1. Make the changes above.
2. Render every preview in the touched files and `MainView`'s "Running"
   at the default, and `SessionView`'s large-font preview at 24.

### Task 3: close

- `ROADMAP.md`: the SU.9 row becomes one line; D3's shortcuts join the
  "after 7b" bullets.
- This plan gains `## Result`.
- `just lint-docs`, `just test`, `just integration`.

## Result

Done 2026-10-13 on `su-ui`, in three commits: Task 1 (`c43143a`), Task 2
(`a53f9cd`) and this close.

**Suites:** `just test` and `just integration` (147 and 75 passed, in its
two test products), with no other test run going. Task 1's tests were
written first and failed to build without `points`.

**Previews:** all twenty in the touched files rendered without errors and
were looked at: `MainView`'s "Running", `InspectorView`'s "Running",
`SettingsView`'s "Settings" (five slots, the thumb in the middle),
`SessionView`'s "Large font" (24 pt), and `ConversationList`'s three,
`MemoryStatusView`'s one, `ToolCardView`'s four and `TranscriptRowView`'s
seven. They were tiled into one image to compare.

**Diverged:**
- **The `points` tests compare within 0.001.** 18 × 0.8 isn't exactly
  14.4 in a `Double`.
- **The sidebar's and inspector's body text takes the base size too,** not
  only their captions: under D1, their system-sized row titles and labels
  were fixed sizes as well.
- **The Swift name stays `transcriptFontSize`.** Renaming it touches
  `SessionView`, so it joins the "after 7b" bullets with the shortcuts.

**Seen, not changed:**
- **The status line truncates in the middle** at 18 pt in `MainView`'s
  preview width (it was already at the body size).
- **The toolbar overflows into `>>`** at 24 pt; the toolbar is 7b's.
- **The sidebar's empty state** is a system `ContentUnavailableView` and
  keeps its own size.

**For the owner in the app:** the first launch opens at 18 pt, because
the key is new; the slider's other four sizes.

**The owner's check, 2026-10-14:** at 18 pt the inspector's long values
(the drafter file, the prefix cache line) wrapped into a column beside
their labels. A row now uses `ViewThatFits`: label and value on one line
when they fit, else the value under its label. A "Narrow" preview at
280 pt shows it.
