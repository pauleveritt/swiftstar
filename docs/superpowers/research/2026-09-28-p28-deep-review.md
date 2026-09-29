# P28 deep review — ds4-engine cut-over

Reviewed at `36e8f8b` (branch `worktree-ds4-engine-subprocess`), against
`before-ds4-engine` (`67109b6`) and ds4-engine `9d96bee0`
(`src/ds4_engine/{ndjson_process,tui_cli,operator,operator_telemetry,session_status}.py`,
`docs/tui.md` TUI.15–17). Verified: `swift build` clean (also with
`-warnings-as-errors`), `swift test` 68/68, `SWIFTSTAR_INTEGRATION=1 swift test`
11/11. No files modified; no app launched.

Severity: **blocker** = ship-stopping; **major** = a user hits it in ordinary
use or the UI/docs state something false; **minor** = cosmetic, edge, or
cleanup.

---

## A. What is broken

### A1 — major — Stop button stays live after the engine dies or is quit mid-turn
`EngineTranscript.isBusy` is set by `appendUser` (`Sources/SwiftStarKit/EngineTranscript.swift:40-44`)
and cleared only by `.awaitingInput`/`.closed` (`:59-63`, `:87-91`). Nothing clears
it on process exit: `EngineController.handleExit`
(`Sources/SwiftStar/EngineController.swift:146-157`) sets `phase = .ended` but leaves
`transcript` alone. The composer button is driven purely by
`controller.transcript.canStop` (`Sources/SwiftStar/AgentView.swift:188-207`), so
after a crash mid-turn the red, animated Stop button remains enabled; pressing it
does nothing (`EngineController.stop`, `:106-113`, bails on `session == nil`).

Repro: send a prompt; `kill -9 $(pgrep -f 'ds4-dogfood tui')`; status bar says
"Ended (exit 9)" while the composer still shows Stop.

Fix: `handleExit` should mark the transcript ended (a `mutating func end()` that
clears the three flags), or `canStop` in the view should also require
`phase == .running`.

### A2 — major — Stop while a prompt is queued during model load hits the exact refusal the spec wanted to avoid
The relay emits `ready` before the parent loads the model
(`ndjson_process.py:224-225`; the parent then sets status "Loading model…",
`tui_cli.py:802`). SwiftStar flips to `.running` on `.ready`
(`EngineController.swift:138`), which enables the prompt field
(`AgentView.swift:186`, `isRunning`). A prompt typed while loading is queued by the
relay (`ndjson_process.py:116-126`, it answers `queued`, which the parser drops
as `.ignored`), but `appendUser` has already set `isBusy` → Stop is enabled →
`stop()` → relay `stop()` refuses "no turn is running"
(`ndjson_process.py:133-135`) → a red error row. Spec revision 5 says Stop must
be disabled outside a turn.

Repro: launch, type while the status bar reads "Loading model — input resumes
at the next pause", Enter, click Stop.

Fix: derive `isBusy` from the engine-acknowledged `.prompt` event (or from
`queued`/`.prompt`), not from `appendUser`; show "Queued" for a prompt the relay
queued.

### A3 — major — No `quitting` phase; a send after "End session" shows garbage
`EngineSession.quit()` (`Sources/SwiftStarAppKit/EngineSession.swift:123-135`)
closes stdin, but `phase` stays `.running` until exit, so the field is still
enabled, the toolbar button still reads "End session", the status bar still
says "Ready"/"Working…". Typing and pressing Enter reaches
`EngineSession.write` → throws `EngineSessionError.notRunning`; the controller
prints `error.localizedDescription` (`EngineController.swift:102`) and, because
`EngineSessionError` (`EngineSession.swift:4-8`) does not conform to
`LocalizedError`, the row reads:
`Could not send: The operation couldn't be completed. (SwiftStarAppKit.EngineSessionError error 0.)`

Fix: add `Phase.quitting`; disable the composer in it; conform the error to
`LocalizedError`.

### A4 — major — Quit mid-turn: bounded by timers, not by the engine; no SIGKILL; a long generation outlives the app
`quit()` writes `{"kind":"quit"}`, closes stdin, SIGTERMs after 5 s
(`EngineSession.swift:123-135`). The relay queues a quit until the next input
pause (`ndjson_process.py:141-149`; `docs/tui.md` TUI.15: "a quit while busy
waits for the turn to end"). SIGTERM is handled by `tui_cli.Termination`
(`tui_cli.py:313-331`) as a `KeyboardInterrupt` → exit 130, but Python signal
handlers run only when the interpreter regains control; `crates/ds4-native/src/bindings.rs`
has no `allow_threads`/`check_signals`, so during one native call (a generation
until the next pause) the SIGTERM is deferred. `EngineController.quit` then gives
up at 10 s (`EngineController.swift:117-129`) and `applicationShouldTerminate`
replies terminate (`Sources/SwiftStar/SwiftStarApp.swift:43-50`). The engine keeps
the model and GPU until its native call returns, then exits (the presenter's
stdout write fails → quit). No SIGKILL escalation exists anywhere (plan B lists
it as deferred).

Consequences a user sees: "End session" during a long answer appears to do
nothing for 5–10 s and then the session ends as "interrupted" (130), never as a
clean quit; Cmd-Q during a long turn leaves `ds4-dogfood` alive after the app is
gone. The ROADMAP's "quits with no orphan" was verified idle only. (Engine docs
TUI.17 report SIGTERM during a turn exited 130 promptly in one live run; turns
pause at every tool call, so in practice the deferral is bounded by the longest
uninterrupted generation.)

Fix: when busy, `quit()` should send `stop` first and wait for `input`, then
`quit`; escalate SIGTERM→SIGKILL after a second grace; keep `.terminateLater`
until `onExit` (or show "Waiting for the engine…") instead of a fixed 10 s.

### A5 — major — The context ring can never leave green at Laguna XS's 20,000 context
`contextWarningTokens = 25_000`, `contextCriticalTokens = 37_500`
(`Sources/SwiftStar/GaugeFormatting.swift:13-14`). Every fixture and the live
probe report `context_size` 20000 (`fixtures/engine/*.ndjson`, `session` event).
`AgentView.swift:258-273` and `InspectorView.swift:13-19` colour by
`contextSeverity(ctxUsed:)`, so the ring is green at 100 % full. BRIEF's binding
rule 1 ("anchor thresholds on absolute ctx_used") was measured on a 150k window
and is now unreachable; the code comment admits "the engine now picks its own
default". The metric the BRIEF says "leads" is the one that lies.

Fix: severity by fraction of the wire's `context_size` (≥ 50 % warning,
≥ 75 % critical), and amend BRIEF rule 1 to say the *display* is fraction-based
while the *finding* is absolute.

### A6 — major — Turn-ending events with no answer are dropped, so the failure shows nothing
`operator.py:382-390` emits `terminal {outcome: tool-limit | context_full | …}`
and ends the session when a turn ends without an answer; `operator.py:308-322`
emits `answer` with empty `text` plus `reason` for an empty Laguna answer.
`EngineWireParser.decode` (`Sources/SwiftStarKit/EngineWireParser.swift:47-112`)
has no `terminal` case (→ `.ignored`) and drops `reason`; the transcript shows
an empty `MarkdownText` row (`EngineTranscript.swift:79-80`) and, seconds later,
"ended without a clean answer — see the session directory". The reason was on
the wire.

Also silently ignored: `queued` (count), `steering_applied`/`steering_unconfirmed`
(a queued prompt was/was not taken), `mentions` (`@path` attachments that were
**missing**), `telemetry_error`, `compacting`/`compacted`/`compact_failed`.

Fix: `terminal` → `.error("Turn ended: <outcome>")`; empty answer → `.error(reason)`;
`queued` → `.notice("Queued (n)")`; `mentions.missing` → `.refused`;
`compacted` → `.notice`.

### A7 — major — Any non-JSON stdout line after `ready` kills the session
`EngineWireParser.parse` returns `.protocolError` for any non-JSON line
(`EngineWireParser.swift:10-12`), and `EngineSession.handle` SIGTERMs on it
(`EngineSession.swift:186-190`). In `--ndjson` mode the *parent* Python process
shares the same stdout pipe as the relay (`tui_cli.py` only redirects fd 1 inside
`native_log`, `:57-78`, during native calls); any stray `print`/warning from a
library, or a Python `DeprecationWarning` routed to stdout, ends the user's
session with "Protocol error: not a JSON object…" followed by "interrupted".
Blank lines are already special-cased (`EngineSession.swift:170`), which shows the
authors anticipated noise. The spec chose "fatal"; I would make only the
handshake fatal and render later junk as a `.notice`.

### A8 — minor — Shift+Return inserts the newline at the end, not at the caret
`AgentView.swift:178-185`: `input += "\n"`. With `TextField(axis: .vertical)`,
`.onSubmit` gives Return-submits / Option-Return-newline natively (verify on
macOS 26) and removes the `onKeyPress` block.

### A9 — minor — The apply command vanishes when a new session starts
`EngineController.start()` resets `transcript`, `metrics`, `sessionDirectory`
(`EngineController.swift:72-74`), so the "Session: … / To take its changes:
ds4-dogfood apply …" row of the previous session is gone the moment the user
clicks Start. Keep the last session directory in the status bar or a
menu item ("Copy apply command").

### A10 — minor — First launch from `/Applications` (or a deep folder) refuses to start
Default workspace anchors on the executable (`EngineController.swift:42-49`,
`ProjectRoot.maxWalkDepth = 5`); an app outside a checkout defaults to `$HOME`,
which is not a git repo → exit 2 "run ds4-dogfood inside a git repository" on
the very first launch. A picked folder more than 5 levels below its git root
also passes the folder itself as `--source` (`EngineController.swift:70-71`).
The engine itself walks all parents (`first_run.repository_root`). Use an
unbounded walk (or `git rev-parse --show-toplevel`), and on first launch open
the folder picker instead of auto-starting.

### A11 — minor — Window close vs app quit
`Window` scene (`SwiftStarApp.swift:14`): Cmd-W hides the only window; the
engine keeps running with no visible surface; the window comes back only via
the Window menu. Since the app is "one engine, one window", implement
`applicationShouldTerminateAfterLastWindowClosed → true` so close = quit.

### A12 — minor — Signal deaths read as exit codes; launch failure reads as "exit -1"
`processExited` uses `terminationStatus` only (`EngineSession.swift:235-239`);
SIGSEGV/SIGKILL show as "exited with code 11/9", and SIGTERM (if the handler is
not yet installed, `tui_cli.py:916`) as "code 15". Launch failure synthesises
`code: -1` (`EngineController.swift:88-90`) → status "Ended (exit -1)". Both
admitted in plan B; both are user-visible strings.

### A13 — minor — `session.context_size` and `interrupted.context_used` are not folded
`EngineMetricsReducer` (`Sources/SwiftStarKit/EngineMetrics.swift:26-42`) takes
context only from `.answer`, so no ring/inspector "Window" until the first
answer, and after a Stop the context readout is stale even though the
`interrupted` event carries `context_used`/`context_size`
(`operator.py:294-300`). `EngineSessionInfo` is decoded and never read.

### A14 — minor — Process-global `signal(SIGPIPE, SIG_IGN)` on every `start()`
`EngineSession.swift:61`. Harmless, but it belongs once in the app delegate.

### A15 — checked, no finding — actor isolation / Sendable
`EngineSession` is `@MainActor`; the `terminationHandler` and
`readabilityHandler` closures capture only `weak self`/a continuation and hop
correctly (`EngineSession.swift:78-81`, `139-152`). `isolated deinit` is Swift
6.2-correct. `@Observable EngineController` is MainActor via
`.defaultIsolation` (explicit `@MainActor` on `MetricsModel`/`AppDelegate` is
redundant). `swift build -Xswiftc -warnings-as-errors` is clean.

### A16 — checked, no finding — exactly-once exit, EOF ordering
The three-flag gate (`exited`, `stdoutDone`, `stderrDone`, `exitFired`;
`EngineSession.swift:241-250`) is correct. If the engine parent is SIGKILLed the
presenter grandchild (which shares the stdout pipe) exits on the dead
multiprocessing pipe (`ndjson_process.py:237-239`), so EOF still arrives.

---

## B. What is wrong or misleading

### B1 — major — The fake engine diverges from `ndjson_process.py` in ways the tests then lean on
`fixtures/engine/fake-ds4-dogfood` vs `Relay`:
- A prompt during a pause **resumes** the replay (fake `:158-161`); the real relay
  **queues** it and answers `{"kind":"queued","count":n}` (`Relay.prompt`).
  `sendWhileBusyIsForwarded` (`Tests/SwiftStarIntegrationTests/EngineSessionTests.swift:187-203`)
  therefore proves the bytes were written, not the queue contract.
- No `stopping` line before `interrupted` (real: `Relay.stop`), admitted.
- `quit` during a pause finishes at once; real waits for the next `input`.
- Non-JSON stdin → `unknown kind '?'`; real → "the line is not JSON".
- Empty prompt accepted; real refuses "a prompt needs a non-empty text".
- SIGTERM → exit 130 instantly; real defers to the interpreter (A4).
- One process; real is parent + presenter grandchild sharing stdout, and the
  "Session artifacts:" line comes from the *parent's* stderr after `close`.
- No model-load phase between `ready` and the first `input` (A2 cannot be
  reproduced in the integration tier).
- `FAKE_ENGINE_EXIT` exists but no test sets it: the exit-1 mapping and the
  stderr tail are untested at the process level (the spec's Testing section
  promised "each exit-code mapping").

### B2 — minor — Tests that cannot fail or pin the wrong thing
- `argumentsAreExact`, `fourAscendingSizes`, `defaultIsThirdSlotNextToLargest`,
  `exitZeroEnded`, `leafNameFallsBackToRootPath`: constants echoed back.
- `noticeWithoutTextFallsBackToKind` (`EngineWireParserTests.swift:141-144`) pins
  the bug that `/clear` renders a system row reading literally "clear".
- `stopMidTurn`/`interruptByteMidTurn` assert "the stop path drops the fixture's
  tool_end" — a property of the fake, not of the engine.
- `badHandshakeTerminates`/`quitAfterTimeoutSendsSIGTERM` assert `code == 130`,
  which is the fake's SIGTERM handler, not a contract.
- Missing (some admitted): unmatched `toolEnd`/`toolResult`, nil-overwrite
  metrics, busy flag after exit (A1), non-JSON after ready → terminate (A7),
  exit-1 with stderr tail, `EngineController` itself (no tests at all).

### B3 — minor — Docs vs code/engine
- BRIEF "prefill / generation tok/s" and the status bar present a *rate*; the
  snapshot's `sync_ms`/`eval_ms`/`prefill_tokens`/`eval_count` are
  **session-cumulative** (engine `docs/tui.md`: "Sync, eval … are session-wide";
  see the `stop.ndjson` checkpoints, `prefill_tokens` 701 → 1110 with `eval_ms`
  unchanged). The number is a session average. Either label it or difference
  consecutive checkpoints.
- BRIEF binding rule 1 vs A5.
- `README.md:33` "Swift 6" → Swift 6.2 / Xcode 26; no build-and-run section
  (`swift run`, `just app`).
- `ROADMAP.md` P28 row: "quits with no orphan" — idle only (A4).
- `docs/glossary.md` "context used … from `answer`" — also from `interrupted`
  and `status_report`; nothing in the glossary defines "agent", yet the UI
  says "Agent"/"Ask the agent…" (B4).
- `fixtures/engine/provenance.md` says "macOS 27.0"; Darwin 27 is macOS 26.
- Spec body "busy/idle from native_start/native_end" and "SubprocessRunner" are
  superseded by the Revisions — fine, but `EngineSession` now uses
  `AsyncStream`, which neither the spec nor the plan mention.
- Plan A "attribution `Claude Opus 5.5`" and "Fable for the final review" are
  workflow noise inside a build record; harmless.

### B4 — minor — Naming that no longer fits
`AgentView`, `AgentBubbles`, `AgentPromptBubble`, `AgentToolCardView`,
`.navigationTitle("Agent")`, "Ask the agent…", "Start a new agent session",
defaults keys `agentWorkspace` and `appShellInspectorPresented`
(`MainView.swift:6`). `SwiftStarAppKit` imports no AppKit
(`EngineSession.swift:1-2`) — `SwiftStarEngine` says what it is.
`EngineController.executableDefaultsKey` is duplicated as the literal
`"engineExecutable"` in `SettingsView.swift:5`.

### B5 — minor — Dead code and dead weight
- `PathAbbreviation.abbreviate` (+3 tests), `MarkdownPreprocess.fenced` and
  `.language(forPath:)` (+3 tests): no caller in `Sources/`.
- `EngineSessionInfo`/`.session`, `PauseMetrics.outputTokens`,
  `EngineToolResult.resultKind`, `EngineTranscript.isAwaitingInput`,
  `EngineSession.interrupt()`: decoded/exposed, never read by the app.
- `ValueGaugeView.text`/`textFontSize`: always `nil`/`0` at all three call
  sites.
- `MetricsModel` (`Sources/SwiftStar/MetricsModel.swift`): a copy of
  `engine.metrics` refreshed by `onChange` (`MainView.swift:24-26`).
- `fixedWidth` (`GaugeFormatting.swift:24-27`): space-padding in a
  proportional font aligns nothing; `.monospacedDigit()` already handles digits.
- `MarkdownPreprocess.deLaTeXed` strips every math delimiter before rendering
  (`MarkdownText.swift:39-41`), so **SwiftMath (7.1 MB bundle) never renders
  math** — it is carried for nothing.
- `Tools/make-icon.swift` (one-shot generator of a committed `.icns`),
  `.claude/commands/goal.md` (retired 2026-08-26),
  `docs/2026-08-26-old-ui-element-inventory.md` + `docs/old_ui.png` (pre-P28
  UI inventory still in the Sphinx toctree).
- `SwiftStar_SwiftStarAppKit.bundle` lingers in `.build/release` from the
  pre-P28 `resources:` and `Tools/make-app.sh:12-14` copies every `*.bundle`
  it finds.

### B6 — minor — Stale comments
`LineBuffer.swift:3-16` ("the agent's line-oriented wires", "capture
producers"); `ProjectRoot.swift:3-9` ("the agent is confined to the app's own
checkout"); `GaugeFormatting.swift:10-12` ("P21 baseline"); `FastTierGuardTool/main.swift:5`
("P2 spec D3"); provenance notes to "DS4 Control"/"agent-mode" in
`MarkdownText.swift`, `ValueGaugeView.swift`, `MarkdownPreprocess.swift` (BRIEF
permits provenance citations; keep, but they now cite a retired project's
retired worktree).

### B7 — minor — FastTierGuard guards the wrong thing
`Package.swift:41-46` attaches the plugin to `SwiftStarKitTests` only, so it
greps *test* sources for `Process(`; a Kit source spawning a process would sail
through. The real gate is `@Suite(.enabled(if:))`. The plugin costs a plugin
target, a tool target, and one build command per test file.

---

## C. What to remove or modernise (macOS 26 / Swift 6.2)

Ranked by value ÷ effort. "Now" = do before the owner's GUI pass or right
after; "Later" = its own small cycle.

### Now

1. **Truthful session state** (A1–A3). Add `Phase.quitting`; clear busy on
   exit; drive `isBusy` from `.prompt`/`queued`; `EngineSessionError:
   LocalizedError`. ~40 lines, three tests (`busyClearsOnExit`,
   `stopDisabledWhileQueued`, `sendWhileQuittingIsRefusedReadably`).
2. **Context severity by fraction** (A5) + BRIEF rule-1 wording. ~10 lines.
3. **Surface the dropped wire events** (A6, A13, `clear`): `terminal`,
   empty-answer `reason`, `queued`, `mentions.missing`, `compacted`,
   `session.context_size`, `interrupted.context_used`; render `/clear` as
   "Conversation cleared". Parser + reducer + ~8 tests.
4. **Quit that actually ends a turn** (A4): `stop` → wait for `input` → `quit`;
   SIGTERM then SIGKILL; `.terminateLater` until `onExit`. ~40 lines; one fake
   flag (`FAKE_ENGINE_IGNORE_SIGTERM`) and one test.
5. **`FileHandle.bytes.lines` instead of `readabilityHandler` + `AsyncStream` +
   `LineBuffer`** (macOS 12+): `Task { for try await line in handle.bytes.lines
   { … } }` per pipe, on the main actor. Deletes `LineBuffer.swift` and its
   tests, `stream(from:)`, both `consume*` line loops; the stderr tail becomes
   "last N lines". `AsyncLineSequence` decodes UTF-8 (invalid bytes are
   replaced), which is what the code already does with `String(decoding:)`.
   ~-70 lines. (`swiftlang/swift-subprocess` is real and gives the same
   `AsyncSequence` stdout plus a structured stdin writer, but it is another
   dependency for what Foundation already provides — skip.)
6. **Drop `FastTierGuard`** (plugin + `FastTierGuardTool`): replace with one
   line in `just test` (`! grep -rn 'Process(\|URLSession' Sources/SwiftStarKit Tests/SwiftStarKitTests`)
   or nothing — the integration gate is the real guard. -2 targets, -50 lines,
   faster clean builds.
7. **Rename `SwiftStarAppKit` → `SwiftStarEngine`** (or fold `EngineSession`
   into Kit; the split's stated reason is "no `Process` in Kit", which a rename
   still honours by naming the process tier). Keep two library targets; the
   executable target cannot be `@testable`-imported cleanly with
   `.defaultIsolation(MainActor.self)`.
8. **Delete the B5 list** and fix B6 comments; rename B4 views to
   `SessionView`/`PromptBubble`/`ToolCardView`; one `enum DefaultsKey`
   shared by `EngineController` and `SettingsView`; key `workspace` (accept
   the one-time loss of the stored folder, or read the old key once).
9. **Inject the controller through the environment**: `@State var engine` in
   the `App`, `.environment(engine)` on the scene, `@Environment(EngineController.self)`
   in `AgentView`/`InspectorView`/`ToolCardView`; delete `MetricsModel` and the
   `onChange` copy in `MainView`. `InspectorView` reads `engine.metrics`
   directly.
10. **Composer**: `TextField("…", text: $input, axis: .vertical)` +
    `.onSubmit(send)` (Return submits; Option-Return inserts a newline on
    macOS — verify on 26); drop `.onKeyPress` (fixes A8). Focus the field in
    `.task` at launch, not only after the first turn.
11. **Transcript scrolling**: `ScrollView { LazyVStack }` with
    `.defaultScrollAnchor(.bottom)` and, if pinning is wanted,
    `.scrollPosition($position, anchor: .bottom)` (both macOS 14+); delete
    `ScrollViewReader`, the `onChange(of: rows)` whole-array compare and the
    `Transaction` dance. Give `TranscriptRow` a stable `id` (UUID assigned on
    append) instead of `\.offset`.
12. **Window lifecycle**: keep `Window` (correct for one engine); add
    `applicationShouldTerminateAfterLastWindowClosed → true` (A11) and
    `.restorationBehavior(.disabled)` (macOS 15+) so a restored window never
    outlives its engine.
13. **README**: a "Build and run" section (`swift run SwiftStar`, `just app`,
    `just integration`), Swift 6.2 / Xcode 26.

### Later (own cycle)

14. **Replace `MarkdownView`** (a pinned fork; 7 transitive packages —
    Highlightr 2.1 MB, SwiftMath 7.1 MB, Litext, cmark, swift-collections,
    LRUCache — plus the `NSViewRepresentable` `sizeThatFits` cache, the
    resource-bundle self-test at launch, and the `*.bundle` copying in
    `make-app.sh`). SwiftUI still has no block-level Markdown renderer;
    `Text(AttributedString(markdown:))` is inline-only. A ~250-line native
    renderer over `apple/swift-markdown` (or the already-linked `MarkdownParser`
    product for one release) covering paragraphs, headings, lists, block
    quotes, fenced code (monospaced `Text` in a rounded background, selectable)
    and tables-as-monospace would cover what a coding model emits. Loses syntax
    colouring; loses nothing on math (already stripped, B5). Value: build
    time, 9 MB of bundles, no fork to rebase, no AppKit in the transcript.
15. **Metrics as deltas**: difference consecutive `checkpoint` snapshots to show
    the last pause's tok/s, and label the cumulative number "session avg".
16. **Liquid Glass affordances** (macOS 26 SDK; toolbars get glass
    automatically): `ToolbarSpacer(.flexible)` to group the Inspector button
    away from the session button; `.buttonStyle(.glassProminent)` on Send;
    `.glassEffect(.regular, in: .capsule)` around the composer;
    `.scrollEdgeEffectStyle(.soft, for: .bottom)` on the transcript so rows
    fade under the composer (verify the macOS availability of the last one
    before relying on it). Small, cosmetic; do after 10–11.
17. **`.fileImporter(isPresented:allowedContentTypes: [.folder])`** instead of
    `NSOpenPanel.runModal()` (`AgentView.swift:60-70`), removing the AppKit
    import from the view.
18. **Try deleting `NativeTooltipView`** (`AgentView.swift:351-381`): `.help()`
    on a `.contentShape(Rectangle())` view has been reliable since macOS 14;
    verify on 26 with the ring gauges before removing.
19. **Info.plist / make-app.sh**: fine as an Xcode-free path. Add
    `LSApplicationCategoryType`, `NSHumanReadableCopyright`, clean stale
    bundles before copying, and an ad-hoc `codesign --force --sign - --deep`
    at the end so a copied `.app` launches on a fresh Mac. Keep the icon script
    out of the tree (or keep it under `Tools/` with a one-line README note).
20. **Strict concurrency polish**: `nonisolated static func command(_:)` /
    `stream(from:)` (they touch no state); nothing else needed —
    `sending`/`@concurrent` have no use here.

### Not worth doing
- `WindowGroup`, an `actor` for `EngineSession`, moving JSON parsing off the
  main actor (payloads are a few KB per pause), swift-subprocess.

---

## Do next (ranked)
1. A1–A3 truthful phases + `LocalizedError` (blocks a credible GUI pass).
2. A5 fraction-based severity.
3. A6/A13 dropped events (`terminal`, empty-answer reason, `queued`,
   `mentions`, `session.context_size`, `clear` text).
4. A4 stop-then-quit + SIGKILL + terminate-when-exited.
5. C5 `bytes.lines`, C6 drop FastTierGuard, C7 rename target, B5/B6 cleanup.
6. C9–C12 environment injection, `onSubmit`, `defaultScrollAnchor`,
   close-quits.
7. Later: C14 native Markdown renderer, C15 delta metrics, C16 glass.
