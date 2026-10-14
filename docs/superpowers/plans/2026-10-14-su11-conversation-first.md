# SU.11: the conversation first

A small cycle (`docs/sdd.md`): one doc, no spec. The owner's run on
2026-10-14: hollow toolbar menus, New Conversation lost in an overflow,
mixed sizes in the inspector, a window titled by the project, and the
running conversation not selected.

## Decisions

The owner made D1 to D3 on 2026-10-14; D4 and D5 follow.

**D1. Every toolbar menu has an icon and its value inside the capsule:**
folder, `cpu` for the model, `gauge.with.needle` for context; still
`.borderlessButton`, so no caption below. The icon gives the left edge
the inset the folder menu already has.

**D2. The window title is the conversation's title.** "New
conversation" while a session runs that isn't listed yet; the project's
name when nothing runs. The folder menu keeps the project.

**D3. New Conversation is the list's first row,** a pencil and "New
Conversation", and the empty list's action. ⌘N moves to File › New
Conversation. The sidebar's toolbar item, which overflowed, goes.

**D4. The running conversation is listed and selected.** When a session's
id first shows up and no listed conversation holds it, the list reloads,
so the row appears and the selection, which already follows
`currentConversationID`, lands on it.

**D5. The inspector's values match their labels:** body size, digits
fixed-width, no monospaced design; the DFlash reason at the same size,
secondary.

## Facts this rests on

- **The list reloads** at a session's end (`EngineController.swift:683`),
  a project switch (`:335`, `:355`) and the list's `.task`, never as a
  session starts. A new conversation's row appears only once it ends.
- **The session id** is set at the first `.pause`
  (`EngineSessionModel.swift:215-218`) or from `resumed`.
- **The selection** already reads `currentConversationID`
  (`ConversationList.swift:63`).
- **`.windowToolbarLabelStyle(fixed: .titleAndIcon)`** put each title
  under its button (owner's screenshot, 2026-10-14; reverted, never
  committed).

## Tasks

### Task 1: Kit rules

**Files:**
- Modify: `Sources/SwiftStarKit/WindowTitle.swift`
- Modify: `Sources/SwiftStarKit/EngineSessionList.swift`
- Tests: `Tests/SwiftStarKitTests/EngineSessionListTests.swift` (or the
  title's existing test)

**Interfaces:**
- `WindowTitle.text(workspace:conversation:active:)`: the conversation's
  title; else "New conversation" if active; else the project's name, else
  "SwiftStar".
- `Conversations.isUnlisted(sessionID:in:) -> Bool`: an id that no
  conversation's `sessionIDs` holds.

**Tests first:** each title branch; listed, unlisted and nil ids.

### Task 2: the controller and the views

**Files:**
- `EngineController.swift`: after an event, an unlisted current id reloads
  the list once per id; `currentConversation` for the title
- `SessionView.swift`: the title
- `ConversationList.swift`: the New Conversation row, the empty state's
  action, no toolbar item
- `SwiftStarApp.swift`: File › New Conversation, ⌘N
- `SessionToolbar.swift`: D1
- `InspectorView.swift`: D5

**Steps:** make them; render the touched files' previews; `just test`.

### Task 3: close

- `ROADMAP.md`: SU.11's row; the punch list's toolbar padding item now
  reads as done or still open, by the owner's look.
- This plan gains `## Result`.
- `just lint-docs`, `just test`, `just integration`; then the owner looks.

## Result

Done 2026-10-14 on `su-ui`, in two commits: the plan (`e072226`) and this
one, which holds all three tasks. Checked in the SU.12 gallery, a real
window over fixtures, by screenshot, with the inspector closed and open.

**Suites:** `just test` and `just integration` (149 and 78 passed), with no
other test run going. `windowTitle` and `unlistedSession` were written
first and failed to build without the new signatures.

**Previews:** `ConversationList`'s three, `InspectorView`'s "Narrow" and
`MemoryStatusView`'s rendered and were looked at.

**Seen in the gallery:** each menu's icon and text in its capsule, with
the same left inset; the title "Answer in one short senten…", the running
conversation; "New Conversation" first in the list; the running row
selected; no overflow.

**Diverged:**
- **A crash, found in the gallery, from `a22fcdd`:** with the inspector
  open in a window under about 1100 pt, `.inspectorColumnWidth` looped
  AppKit's layout until it threw ("more Update Constraints in Window passes
  than there are views"). It's back to the plain `.frame`, which doesn't
  crash but keeps the divider stiff; the punch list holds what the probes
  ruled out.
- **The GPU figures stay on one line:** at 900 pt with the inspector open
  they wrapped beside the rates.
- **The inspector's type** is the labels' font with fixed-width digits;
  the DFlash reason is at the same size, secondary.

**For the owner in the app:** the toolbar against Xcode's; a new
conversation's row appearing and selected after its first answer; File ›
New Conversation (⌘N).
