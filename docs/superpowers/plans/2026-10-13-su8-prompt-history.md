# SU.8: prompt history

A small cycle (`docs/sdd.md`): one doc, no spec. ↑ and ↓ in the composer
step through earlier prompts.

## Decisions

The owner made these on 2026-10-13.

**D1. This conversation's prompts, from the transcript.** No new storage.
A resumed conversation brings its prompts back; a new one starts empty.

**D2. Arrows recall only while the field is empty or unedited.** ↑ and ↓
step through history while the field is empty or still shows a recalled
prompt unchanged. Once it's edited, the arrows move the cursor. No draft is
ever replaced.

**D3. Everything typed, slash commands included.** Never the app's own
Analyze prompt. Repeats in a row collapse to one.

## Facts this rests on

- **Prompts are `.user` rows** (`EngineTranscript.swift:118-121`), and a
  resume rebuilds them from the engine's turns (`:154-158`).
- **The Analyze prompt's row is its shown label,**
  `EngineAnalysis.promptShown` (`EngineSessionModel.swift:279-282`). If a
  fork is relaunched, its rebuilt row is the full prompt, which ends with
  `EngineAnalysis.instruction` (`EngineAnalysis.swift:51-53`).
- **Slash commands** go through the same `send`, so they're `.user` rows
  too.
- **`onKeyPress`** catches a key while the field has focus; `.ignored`
  lets the field handle it (Apple docs, checked 2026-10-13).
- **The cursor's visual line isn't knowable** from SwiftUI once text
  wraps, which is why D2 avoids line rules.

## Tasks

### Task 1: the history in Kit

**Files:**
- Create: `Sources/SwiftStarKit/PromptHistory.swift`
- Test: `Tests/SwiftStarKitTests/PromptHistoryTests.swift` (new)

**Interfaces:**
- `public struct PromptHistory: Equatable, Sendable`
  - `static func entries(from rows: [TranscriptRow]) -> [String]`: the
    `.user` texts, oldest first, without the Analyze prompt (equal to
    `promptShown`, or ending with `instruction`), repeats in a row
    collapsed.
  - `mutating func up(current: String, entries: [String]) -> String?`
  - `mutating func down(current: String, entries: [String]) -> String?`
  - Both return the field's new text, or nil when the arrow should move
    the cursor.
- **The rules:**
  - **Recall is allowed** when `current` is empty, or equals the last
    recalled text. Otherwise both return nil, and an empty field forgets
    the position.
  - **↑** goes one older, starting from the newest; at the oldest it stays
    there and returns it (handled, so the cursor doesn't jump).
  - **↓** goes one newer; past the newest it returns `""` and forgets the
    position. With no position, ↓ returns nil.
  - **No entries:** both return nil.

**Tests first** (each fails before the code exists): entries filtering and
collapsing; ↑ from empty gives the newest; ↑↑ the one before; ↑ at the
oldest stays; ↓ back to newer and then `""`; an edited recall returns nil
both ways; an emptied field restarts from the newest; no entries gives
nil.

### Task 2: the composer

**Files:**
- Modify: `Sources/SwiftStarUI/Session/ComposerView.swift`

**Steps:**
1. `@State private var history = PromptHistory()`.
2. On the field, `.onKeyPress(.upArrow)` and `.onKeyPress(.downArrow)`:
   call `up` or `down` with `input` and
   `PromptHistory.entries(from: controller.transcript.rows)`; a non-nil
   result sets `input` and returns `.handled`, nil returns `.ignored`.
3. Render the four previews: unchanged.
4. Owner: in the app, send two prompts, then ↑ ↑ ↓ ↓; type a multi-line
   draft and check ↑ moves the cursor.

### Task 3: close

- `ROADMAP.md`: the SU.8 row becomes one line with this plan's link.
- This plan gains `## Result`.
- `just lint-docs`, `just test`, `just integration`.
