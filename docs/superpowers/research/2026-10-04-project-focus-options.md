# Project focus and switching: options for SU.7

> Design notes from a 2026-10-04 conversation with the owner, recorded so
> SU.7's brainstorm starts from them. These are options and a
> recommendation, not a decision; SU.7 has not been brainstormed yet.

## The problem

Apps like Claude Desktop and Codex show every project and its chat sessions
as a tree in the left-hand sidebar. You see all your projects at once, which
makes it hard to focus on one. The owner wants SwiftStar to focus on one
project while still making it natural to jump between projects. Neither a
window per project nor tabs in the main window felt right as a starting
assumption.

## What shapes the answer

- **SwiftStar is workspace-first, not chat-first.** Every session runs
  inside one checkout, so it is closer to an IDE than to a chat app. On the
  Mac, developer tools commonly use one window per project or workspace:
  Xcode, VS Code, Cursor, Zed, Nova and JetBrains.
- **One engine, one window.** Each session holds a `ds4-dogfood` engine with
  a multi-GB model loaded. `SwiftStarApp` therefore uses a single `Window`,
  not a `WindowGroup`: a second window would start a second engine competing
  for the GPU (`Sources/SwiftStar/SwiftStarApp.swift`). Several project
  windows only become reasonable once ds4-engine can serve or resume more
  than one session. The Backlog's "session picker" entry records that resume
  isn't reachable over `--ndjson` today.

## Recommendation: one window, one project at a time

1. **The project is the window's identity, not an item in a sidebar.** The
   window title shows the project name, and `.navigationSubtitle` shows the
   path or branch. Each project gets a colour or symbol in the toolbar so
   you can see where you are at a glance.
2. **The sidebar shows only the current project's sessions.** Use
   `NavigationSplitView` with sessions in the sidebar, the transcript in the
   detail, and metrics in the trailing `.inspector`. Other projects don't
   appear in the sidebar at all; that is where the focus comes from.
3. **Switching projects is fast but deliberate.**
   - A toolbar project switcher, growing out of today's "Choose folder" menu:
     recents first, each showing its last-active session and a "busy" dot if
     a turn is running. Xcode's scheme picker and Safari's profile switcher
     are the models.
   - A keyboard quick switcher in the style of Xcode's Open Quickly, on
     ⌘⇧O or ⌘K.
   - File › Open Recent and the Dock menu's recent items.
   - Switching mid-turn asks first, because it stops and restarts the
     engine.
4. **An optional compact project rail.** Icons on the far left, like Slack
   or Discord, show that other projects exist without showing their
   sessions. This could be a setting rather than the default, since it
   brings back some of the "everything at once" feeling.
5. **Multiple windows later, gated on the engine.** If ds4-engine gains
   multi-session or resume support, move from `Window` to
   `WindowGroup(for: ProjectID.self)`. That gives native macOS window tabs
   for free (Merge All Windows, the ⌘⇧\ tab overview), plus Stage Manager and
   Spaces for focus. Users then choose windows or tabs themselves, as in
   Xcode, Finder and Safari. Each window keeps the project-scoped split view
   from items 1–3.

## Look and feel on macOS 26

- Let the system's Liquid Glass sidebar and toolbar do the work.
- Make the toolbar customisable with `.toolbar(id:)`.
- Use SF Symbols for session state: idle, running, needs input.
- Avoid custom chrome. The target feel is Mail or Notes with a transcript in
  the middle.

## Related

- Backlog, "Front-end": the session picker and session browser entries. A
  per-project session list depends on the same engine resume support.
- SU.6 (UI tweaks) includes "first-launch workspace". Its first-run flow
  should agree with the project switcher.
