# Old UI element inventory — `docs/old_ui.png`

`docs/old_ui.png` is a screenshot of a "DS4 Agent" window — the same agent
window this repo's [`AgentView.swift`](../Sources/SwiftStar/AgentView.swift)
is a port of. This doc names every visible UI element in the screenshot and
cross-tabulates it against the SwiftUI that produces it, in both the source
app (`ds4-control`, worktree `agent-mode`) and this repo (`swiftstar`).

Source app read: `~/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/`

## Element-by-element

### 1. Title bar — "DS4 Agent"

Traffic-light window controls (red/yellow/green) at top-left, window title
"DS4 Agent" centered next to them.

- **ds4-control**: `WindowChrome.windowOpened(title: "DS4 Agent")`, called
  from `AgentView.onAppear` — [`AgentView.swift:131`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L131).
  `WindowChrome` is the app's own window-registration shim (menu-bar-extra
  apps have to announce their own windows), not a SwiftUI view.
- **swiftstar**: `.navigationTitle("Agent")` — [`AgentView.swift:58`](../Sources/SwiftStar/AgentView.swift#L58).
  No `WindowChrome` equivalent; swiftstar isn't a menu-bar-extra app.

### 2. Transcript region (the large scrolling area)

Everything from just under the title bar down to the divider above the input
field is the transcript: a top-to-bottom, left-aligned scroll of turns.

- Both apps: `ScrollViewReader` + `ScrollView` + `LazyVStack(alignment:
  .leading)`, auto-scrolled to a bottom sentinel on new content.
  - ds4-control: [`AgentView.swift:18-42`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L18-L42),
    keyed on the whole `session.items` array (not `.count`) because a
    streaming `text` event mutates the trailing item in place.
  - swiftstar: [`AgentView.swift:133-150`](../Sources/SwiftStar/AgentView.swift#L133-L150),
    keyed on `controller.transcript.rows.count` and scrolled by row index
    rather than a stable `id`.

### 3. Code block — "Return a greeting for ds4." / `hello_ds4()` function

A syntax-highlighted Python code card: docstring in salmon/orange, `return`
and `if __name__` in pink/magenta keywords, plain text in white/gray, on a
dark card background. This is the *body* of a `write`-style tool call,
rendered as a fenced code block.

- **ds4-control**: `AgentItemView.contentView(_:call:)` —
  [`AgentItemView.swift:268-278`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentItemView.swift#L268-L278).
  Once the call has finished (`call.ok != nil`), the `.content` param is
  wrapped in a language-tagged fence via `Self.fenced(value,
  language: Self.language(forPath: call.path))` (`.swift:281-305`) and handed
  to `MarkdownText`, which does the actual syntax highlighting. While still
  streaming (`call.ok == nil`) it's plain monospace text instead — no
  highlighting mid-stream.
- **swiftstar**: `ToolCardView` — [`AgentView.swift:6-39`](../Sources/SwiftStar/AgentView.swift#L6-L39).
  Params render as plain `name: value` caption lines
  (`.swift:16-20`); there is no dedicated "this param is a file body, syntax
  highlight it as a code block" path like `contentView`/`fenced`/`language`.
  A `write` call's file content would currently print as one long
  `content: ...` caption line, not a highlighted card.

### 4. Tool-call card — "write test_hello_ds4.py"

A rounded-rect card, dark background, thin separator-colored border. Header
row: a document/write icon, then the bold text "write test_hello_ds4.py".
Below the header, the same kind of syntax-highlighted code block as #3 (the
new test file's contents).

- **ds4-control**: `AgentItemView.card(call:)` —
  [`AgentItemView.swift:107-134`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentItemView.swift#L107-L134)
  (padding 10, `RoundedRectangle(cornerRadius: 10)` fill +
  `.separatorColor` stroke). The header text itself is built by
  `Self.headerText(call)` (`.swift:178-186`): `"\(call.name) \(call.path)"`
  for anything with a path param — hence "write test_hello_ds4.py" rather
  than a generic "Write" label. The icon comes from `Self.icon(for:
  call.name)` (`.swift:324-336`); `write` → `"doc.badge.plus"`. Because
  `write`/`edit`/`read` are in `quickLookEligibleToolNames`
  (`.swift:139`), this header is also a clickable Quick Look button when the
  named file exists on disk (`headerView`, `.swift:144-161`).
- **swiftstar**: `ToolCardView` — [`AgentView.swift:6-39`](../Sources/SwiftStar/AgentView.swift#L6-L39).
  Card chrome exists (`.background(.quaternarySystemFill)`,
  `RoundedRectangle(cornerRadius: 6)`, padding 8) but is visually plainer —
  no border stroke. Header is `Image(systemName: "wrench.and.screwdriver")` +
  `card.name` for *every* tool, not `icon(for:)`'s per-tool-name icon set,
  and not `headerText`'s "name + path" convention — so a write call shows
  as a wrench-icon "write" card, not a document-icon "write
  test_hello_ds4.py" card. No Quick Look affordance at all.

### 5. Narration line — "Now let me run the tests with uv:"

Plain prose text between the two tool cards, left-aligned, normal (not
monospace) font — the assistant's own commentary, not a tool card.

- **ds4-control**: `AgentItemView.assistantView`/`proseView` —
  [`AgentItemView.swift:70-93`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentItemView.swift#L70-L93),
  rendered through `MarkdownText`/`StreamingMarkdownText` depending on
  whether this item is the transcript tail.
- **swiftstar**: `rowView`'s `.content` case — [`AgentView.swift:157`](../Sources/SwiftStar/AgentView.swift#L157) —
  plain `Text(text).font(.body)`, no Markdown rendering.

### 6. Tool-call card — `$ uv run pytest test_hello_ds4.py -v`

Same card chrome as #4, but a terminal glyph in the header and a `$
<command>` header line instead of `name path` — this is a `bash` call, not a
`write`. Below the header: `refresh_sec: 5` and the pytest banner
(`===== test session starts =====`, platform/rootdir/configfile lines) in
plain monospace — this is the shell command's **stdout**, not code, so it is
never markdown- or syntax-highlighted.

- **ds4-control**: same `card(call:)` as #4, but `Self.headerText` special-
  cases `bash`: `"$ \(command)"` where `command` is the call's
  `.bashCommand`-kinded param (`.swift:178-181`); icon is `"terminal"`
  (`.swift:326`). Output renders via `cardBody`'s `if !call.output.isEmpty`
  branch (`.swift:217-228`) — always plain
  `Text(call.output).font(.system(.caption, design: .monospaced))`, deliberately
  never through `MarkdownText`, so a `#`-prefixed pytest line can't be
  misread as a Markdown heading.
- **swiftstar**: `ToolCardView`'s `card.output` block —
  [`AgentView.swift:21-29`](../Sources/SwiftStar/AgentView.swift#L21-L29) —
  same plain-monospace-in-a-sub-card treatment, correctly never Markdown.
  But the header is still the generic wrench+name (see #4) — no `$ uv run
  pytest …` command-line header, no distinct bash icon.

### 7. Input field — "Ask the agent…" placeholder

A pill-shaped (fully rounded) text field along the bottom, subtle 0.5pt
secondary-opacity border, placeholder text "Ask the agent…", growing
vertically for multi-line input.

- **ds4-control**: [`AgentView.swift:46-66`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L46-L66) —
  `TextField("Ask the agent…", text: $input, axis: .vertical)`,
  `.lineLimit(1...15)`, `RoundedRectangle(cornerRadius: 20)` background/stroke.
  Return submits; Shift+Return inserts a newline (`onKeyPress`).
- **swiftstar**: [`AgentView.swift:191-213`](../Sources/SwiftStar/AgentView.swift#L191-L213) —
  same shape and same Return/Shift+Return handling, but placeholder text is
  "Message the agent" rather than "Ask the agent…".

### 8. Send/stop button (upward arrow-in-circle, cut off at the right edge)

A large (28pt) circular button, `arrow.up.circle.fill` glyph when idle,
swaps to a pulsing `stop.circle.fill` while the agent is generating (screen
is cropped before the button in this particular capture, but it's the same
control as ds4-control's and swiftstar's send button).

- **ds4-control**: [`AgentView.swift:68-84`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L68-L84) —
  icon swap keyed on `session.isInterruptible`;
  `.symbolEffect(.variableColor.iterative, isActive: session.isInterruptible)`
  animates the stop icon while interruptible. Color: red when stoppable,
  accent when sendable, secondary when disabled.
- **swiftstar**: [`AgentView.swift:215-231`](../Sources/SwiftStar/AgentView.swift#L215-L231) —
  same icon swap and red/accent coloring, but no `.symbolEffect` animation on
  the stop state.

### 9. Bottom status row — "Prompt 302 / Decode 64 tok/s — Ready"

Caption-sized secondary-colored text along the very bottom, left-aligned,
fixed-width numeric fields ("302", "64") so only the trailing message text
shifts width tick to tick.

- **ds4-control**: `AgentView.statusText` / `promptDecodeLine` —
  [`AgentView.swift:142-172`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L142-L172) —
  `String(format: "Prompt %4.0f / Decode %4.0f tok/s — %@", …)`, built from
  `session.lastPrefillTPS`/`lastGenTPS` (view-layer ratchets, not a raw read
  of `engineStatus`, to avoid missing an intermediate nonzero reading — see
  the doc comment there). `.monospacedDigit()` +
  `.contentTransition(.numericText())` for the tick-to-tick animation.
- **swiftstar**: `AgentView.bottomStatusText` / `AgentStatusText.promptDecodeLine` —
  [`AgentView.swift:296-305`](../Sources/SwiftStar/AgentView.swift#L296-L305),
  logic factored out into `SwiftStarKit`'s
  [`AgentStatusText.swift`](../Sources/SwiftStarKit/AgentStatusText.swift)
  rather than living as a `static func` on the view itself. Same
  `.monospacedDigit()`/`.contentTransition(.numericText())` treatment
  (`.swift:264-266`).

### 10. "End session" button (bottom-right, off-screen in this capture)

Present in both apps' bottom bar, disabled once the session is already off.

- **ds4-control**: [`AgentView.swift:123-124`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L123-L124) —
  `.disabled(session.state == .off)`.
- **swiftstar**: [`AgentView.swift:288-289`](../Sources/SwiftStar/AgentView.swift#L288-L289) —
  `.disabled(controller.state == .stopped || controller.state == .stopping)`.

### Not visible in this screenshot, but part of the same bar (both apps)

Two small `ValueGaugeView` ring gauges sit between the status text and "End
session": an agent-memory-footprint ring and a context-window-fill ring,
each with a `.help()` tooltip. ds4-control:
[`AgentView.swift:97-122`](file:///Users/pauleveritt/projects/ds4-control/.claude/worktrees/agent-mode/Sources/DS4Control/Views/AgentView.swift#L97-L122);
swiftstar: [`AgentView.swift:268-287`](../Sources/SwiftStar/AgentView.swift#L268-L287)
(swiftstar has its own [`ValueGaugeView.swift`](../Sources/SwiftStar/ValueGaugeView.swift)
and severity logic in `DialLogic`, vs. ds4-control's `MetricSeverity`).

## Summary: gaps between swiftstar and the ds4-control source

| Element | ds4-control | swiftstar | Gap |
|---|---|---|---|
| Tool card header | icon-per-tool-name + `"name path"` / `"$ command"` | generic wrench icon + `card.name` only | No per-tool icon, no path/command in header |
| Tool card body (file content) | syntax-highlighted fenced Markdown once call completes | plain `name: value` caption line | No code highlighting for `write`/`edit` content |
| Tool card Quick Look | clickable header opens Quick Look for `write`/`edit`/`read` | none | Feature absent |
| Assistant prose | rendered through `MarkdownText`/`StreamingMarkdownText` | plain `Text` | No Markdown rendering |
| Thinking disclosure | collapsible `ThinkingDisclosure` above prose | plain italic `Text` in transcript | No collapse affordance |
| Window title | `WindowChrome.windowOpened(title: "DS4 Agent")` | `.navigationTitle("Agent")` | Cosmetic only — different app shape (menu-bar-extra vs. not) |
| Input placeholder | "Ask the agent…" | "Message the agent" | Cosmetic |
| Stop-button animation | `.symbolEffect(.variableColor.iterative, …)` | none | Cosmetic |
| Transcript scroll anchor | keyed on stable `item.id`, keyed on the whole array's `Equatable` conformance | keyed on row `.offset` / `.count` | Robustness gap — offset-keyed `ForEach` reflows on any row-count change |

The biggest functional gaps are all in tool-card fidelity: swiftstar's
`ToolCardView` (a single ~35-line view) is a stand-in for ds4-control's
`AgentItemView.card(call:)` machinery (icon-per-tool, header text
convention, Quick Look, syntax-highlighted content, diff rendering for
`edit` calls) — none of that richness has been ported yet.
