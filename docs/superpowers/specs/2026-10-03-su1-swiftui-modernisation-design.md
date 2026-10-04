# SwiftStar SU.1 design: SwiftUI modernisation

**Date:** 2026-10-03
**Status:** design, re-verified against current code before writing
**Phase:** SU — cycle SU.1 (first cycle of the SU phase)
**Source:** ROADMAP.md's SU.1 row (carried from P29.7, itself drawn from the
[P28 deep review](docs/superpowers/research/2026-09-28-p28-deep-review.md)'s
A8 finding and items 9–12 of its recommendations). Re-verified against the
code as it stands after P32 (renames, dead-code deletion already landed) —
one of the four original items is already done; one sub-claim in another is
wrong about current code and dropped.

## Goal

Four SwiftUI-modernisation items, no behavior change except the one real fix
(A8, Option-Return inserting at the caret): inject `EngineController` via
`@Environment`; replace the composer's manual `.onKeyPress` with `.onSubmit`;
replace the transcript's manual scroll-to-bottom with `.defaultScrollAnchor`;
make closing the single window quit the app, and stop state restoration from
fighting the one-engine-one-window rule.

## 1. Inject `EngineController` via `@Environment`

**Already partly done.** The P29.7/SU.1 ROADMAP text pairs this with
"delete the manual `onChange` copy" — that was `MainView`'s `MetricsModel`
sync, deleted in P32 Task 4 (`eeb49fe`). `InspectorView` already reads
`engine.metrics` directly. Nothing left to delete; this item is now just the
injection itself.

Today `SwiftStarApp` holds `@State private var engine = EngineController()`
and passes it down by initializer: `MainView(engine: engine)` →
`SessionView(controller: engine)` / `InspectorView(engine: engine)`. 49
`controller.`-prefixed call sites in `SessionView.swift` alone.

Change: `.environment(engine)` on the `Window` scene's content in
`SwiftStarApp.swift`; `MainView`, `SessionView`, `InspectorView` each read
`@Environment(EngineController.self) private var controller` (or `engine`,
matching each file's current local name) instead of a stored `let`
property. `EngineController` is already `@Observable`, so this is a
mechanical change, not a new pattern.

`ToolCardView` is **not** included, though the deep review's item 9 named it:
it only uses `card: EngineToolCard` and `workspace: URL?`, never the
controller. Injecting the controller there would add a dependency it
doesn't need — re-verified by reading the file, not carried over from the
review text.

## 2. Composer: `.onSubmit` instead of `.onKeyPress`

`SessionView.swift:306-313` today: `.onKeyPress(keys: [.return], phases:
.down)` — Shift+Return appends `"\n"` to the end of `input` (not at the
caret) and returns `.handled`; plain Return calls `send()`. This is exactly
[A8](docs/superpowers/research/2026-09-28-p28-deep-review.md#a8): the
newline always lands at the end of the text, not where the cursor is,
because the code manipulates the bound `String` directly instead of letting
the text control's own editing handle it.

**The fix the review proposed, re-verified:** `TextField(axis: .vertical)` +
`.onSubmit { send() }`, dropping `.onKeyPress` entirely. On a vertical-axis
`TextField`, plain Return submits (via `.onSubmit`) and Option-Return inserts
a newline at the caret — native editing, so A8 cannot recur. `SubmitTriggers`
and `onSubmit(of:_:)` are documented, real APIs (confirmed via
`DocumentationSearch`); what is **not** independently confirmed is the exact
Return-submits/Option-Return-newlines split for a vertical-axis field on
macOS 26 specifically — the deep review flagged this itself ("verify on
26"), and no documentation search surfaced the specific interaction. This is
cheap and fast to confirm by running the built app and trying both keys —
**the plan's first step**, before anything else in this item lands, exactly
because the rest of the item assumes the answer is yes.

**Also fixes a related gap**, found by re-reading the file for this item:
there is no `.task` focusing the composer at launch — `inputFocused` is
currently set `true` only when `composerState.canStop` goes false (i.e.,
after a turn ends), so a fresh launch leaves the field unfocused until the
first turn completes. Add a launch-time focus alongside the `onSubmit` swap.

**The key convention changes** from Shift+Return (current) to Option+Return
(native vertical-`TextField` behavior) for inserting a newline without
submitting. This is a user-visible keybinding change, not just an internal
refactor — flagged here rather than folded silently into "modernisation."

## 3. Transcript: `.defaultScrollAnchor(.bottom)`

`SessionView.swift:200-229` today: a `ScrollViewReader` wrapping the
`ScrollView`, an `.onChange(of: controller.transcript.rows)` comparing the
whole array (a tool card fills in place, so `.count` alone would miss it),
and a no-animation `Transaction` around `proxy.scrollTo(last, anchor:
.bottom)`.

Replace with `.defaultScrollAnchor(.bottom)` on the `ScrollView` — a real,
documented modifier (confirmed via `DocumentationSearch`) built for exactly
this: initial position at the bottom, and the scroll view consults the
anchor again when content size changes, without a `ScrollViewReader` or an
`onChange` at all. Delete the `ScrollViewReader`, the `onChange`, and the
`Transaction` dance.

**Stable row ids: already true, no change needed.** The deep review's item
11 suggested giving `TranscriptRow` a UUID assigned on append, instead of
`\.offset`. Re-verified by reading `EngineTranscript.swift`: every mutation
is `rows.append(...)` or an in-place `rows[i] = .tool(card)` (the tool-card
fill-in); rows are never removed or reordered. `\.offset` is already a
stable identity for a row's whole lifetime, as the file's own comment
states. The ROADMAP's SU.1 wording ("with stable row ids") already reflects
this — it is a property to preserve across the change, not one to add.

## 4. Window lifecycle: close quits, state restoration disabled

Today: `Window("SwiftStar", id: "main")`, no `.restorationBehavior`, and
`AppDelegate` implements `applicationShouldTerminate` (wait for the engine to
exit before replying) but not
`applicationShouldTerminateAfterLastWindowClosed`. Without that second
method, AppKit's default leaves the app running (just a menu bar, no
windows) after the window closes — confirmed via `DocumentationSearch`: the
method's absence means no termination is triggered on last-window-close.

Two independent, additive changes:
- `AppDelegate.applicationShouldTerminateAfterLastWindowClosed(_:) -> Bool {
  true }` — closing the window now routes through `terminate:` →
  `applicationShouldTerminate`, so the existing engine-quit-wait logic
  already covers this path; no new quit logic needed.
- `.restorationBehavior(.disabled)` on the `Window` scene (confirmed real,
  documented `Scene` modifier) — macOS's system-wide state-restoration
  setting must not reopen a second "SwiftStar" window or resurrect stale UI
  state across launches, which would fight the one-engine-one-window rule
  `SwiftStarApp.swift`'s own comment already states.

## Out of scope

README's "Build and run" section (named in the original P29.7 bullet) is
current as written — re-verified, nothing to change. The deep review's
broader item-9 suggestion to inject the controller into `ToolCardView` too
is dropped (see `## 1`). SU.1 touches `Sources/SwiftStar/` only; no
`SwiftStarKit`/`SwiftStarEngine` change.

## Success criteria

1. `swift build`, `just test`, `just integration` green after every task.
2. Live check (built `.app`, see plan Task 1): Return submits, Option-Return
   inserts a newline at the caret, both on first launch (composer focused)
   and mid-conversation.
3. Live check: closing the window quits the app (process exits, no orphan
   engine — same check `quitMidTurnEndsTheEngine`-style tests already use
   for Cmd+Q, done manually since this is a window-manager interaction no
   test harness drives).
4. `grep -rn "onKeyPress\|ScrollViewReader" Sources/SwiftStar/` returns
   nothing for the composer/transcript (other legitimate `onKeyPress`/
   `ScrollViewReader` uses, if any exist elsewhere, are unrelated — check by
   file).
