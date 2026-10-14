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
