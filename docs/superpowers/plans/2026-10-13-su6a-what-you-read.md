# SU.6a: What You Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the 27B's full reply as the answer, with its summary under
it. Show "Queued" only when the engine reports it, title the window by its
workspace, and leave indented code alone.

**Architecture:** The merge is a Kit rule in `EngineTranscript`'s fold, so
the view only draws `TranscriptRow.answer`'s new `reply`. The window title
comes from a pure Kit helper. The indented-code rule extends
`MarkdownPreprocess.deLaTeXed`'s existing line loop. Plans here list files,
interfaces and tests, not bodies (`docs/sdd.md`).

**Tech Stack:** Swift 6.4, SwiftUI on macOS 26, Swift Testing.

**Spec:** [`docs/superpowers/specs/2026-10-13-su6a-what-you-read-design.md`](../specs/2026-10-13-su6a-what-you-read-design.md)

## Global Constraints

- **Builds:** warnings are errors on our own targets (`Package.swift:13`).
  There are no new package dependencies.
- **Fast tier:** spawns nothing (`just test`'s grep).
- **Tests:**
  - Every new test is shown to fail first: break the line it pins, watch
    it fail, restore.
  - New cases join the existing tables wherever one fits.
- **Test bodies stay at function level.** Swift 6.4 can give a closure
  inside `#expect(...)` and a same-typed sibling in one enclosing closure the
  same identity (`Tests/SwiftStarIntegrationTests/Support.swift`).
- **UI files:** every `#Preview` in a touched file under
  `Sources/SwiftStarUI/` is rendered with `RenderPreview`, scheme
  `SwiftStarUI`, and looked at (the `ui-loop` skill).
- **Copy, verbatim from the spec:**
  - "Summary: …"
  - the title fallback "SwiftStar"
  - the placeholder "Ask about this project…"
- **Close:** ROADMAP, the Result and `just lint-docs` fold into the last
  task's commit. There are no separate close commits.

## Review Focus

1. **A turn with several narrations,** some before tools and one at the end.
   Only the last absorbs the answer; earlier ones stay narration rows.
   Pinned in Task 1.
2. **A narration followed by a stop rather than an answer.** The narration
   stays, followed by "Stopped.". Pinned in Task 1.
3. **Texts equal apart from surrounding whitespace or newlines.** They count
   as equal, so there is no summary line. Pinned in Task 1.
4. **An indented fence marker** (`    ` followed by three backticks) after a
   blank line is code. It must not open a fence that swallows the prose
   after it. Pinned in Task 3.
5. **An indented paragraph inside a list item** is kept raw. That is the
   accepted trade-off; it is pinned in Task 3 so a later change sees it.

---

### Task 1: The reply is the answer's body

**Files:**
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift`
  - `:74-83`: the `TranscriptRow` case
  - `:88`: the invariant comment
  - `:192-198`: the `.answer` fold
- Modify: `Sources/SwiftStarUI/Session/TranscriptRowView.swift`
  - `:22-34`: the `.answer` case
  - `:75-83`: the "Answer with summary" preview
- Modify: `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`
  - `:18-27`: `toolReadFixtureBuildsRows`
  - `:202`: the pattern in `resumedReplacesRows`
  - the `answerCases` table
- Check: `Sources/SwiftStarUI/PreviewSupport/PreviewFixtures.swift:40`. It
  applies an answer with no narration, so it needs no change; confirm it
  compiles.

**Interfaces:**
- Produces:
  - `TranscriptRow.answer(EngineAnswer, reply: String? = nil)`. Existing
    `.answer(a)` constructions still compile; pattern sites become
    `.answer(let a, _)` or `.answer(let a, let reply)`.
  - The fold rule:
    1. On `.answer(a)` with non-blank `a.text`, find the last index whose
       row isn't `.user`.
    2. If that row is `.narration(n)`:
       - texts equal after trimming whitespace and newlines: replace it
         with `.answer(a, reply: nil)`
       - otherwise: replace it with `.answer(a, reply: n)`
    3. Otherwise, append `.answer(a)` as today.
    4. Blank `a.text` keeps today's error-row path untouched.

- [ ] **Step 1: Write the failing tests.** In `EngineTranscriptTests`, add
  an `AbsorbCase` table: label, events to apply after `appendUser("go")`,
  and the expected rows. Use a test named `absorb`. The rows:
  - `narrationBecomesTheAnswerBody`: narration "full reply", then answer
    "short" → the rows are `.user("go")` and
    `.answer(short, reply: "full reply")`.
  - `equalTextsShowOnce`: narration "same\n", then answer " same" →
    `.answer(" same", reply: nil)`, with no narration row.
  - `toolBetweenBlocksTheMerge`: narration, tool start/end, answer → the
    narration row is kept, then the card, then `.answer(a, reply: nil)`.
  - `onlyTheLastNarrationMerges` (Review Focus 1): narration "plan", tool,
    narration "reply", answer → `.narration("plan")`, the card, then
    `.answer(a, reply: "reply")`.
  - `stoppedTurnKeepsNarration` (Review Focus 2): narration, then
    `.interrupted` → the narration row is kept and "Stopped." follows.
  - `emptyAnswerKeepsNarration`: narration, then an answer with "" →
    the narration row, then `.error("No answer — the model stopped without
    answering")`.
- [ ] **Step 2: Write the named test** `promptBetweenNarrationAndAnswerStaysPending`:
  - narration, then `appendUser("more")`, then answer
  - row 1 is `.answer(a, reply: n)`
  - row 2 is `.user("more")`
  - `isPending(rowAt: 2)` is true
- [ ] **Step 3: Extend `toolReadFixtureBuildsRows`.** Assert that no
  `.narration` row is left. Assert that the one answer row's `reply` starts
  with the fixture narration's first words, "`Package.swift` declares".
- [ ] **Step 4: Run them and see them fail.** Run
  `swift test --filter EngineTranscriptTests`. Expected: a compile failure,
  because `reply:` doesn't exist yet.
- [ ] **Step 5: Implement the case, the fold and the comment.**
  - Update `resumedReplacesRows`' pattern to `.answer(let a, _)`.
  - The invariant comment reads: rows are never removed or reordered; a
    narration row may absorb its turn's answer.
- [ ] **Step 6: Run them and see them pass.** Then run the break check:
  make the fold always append, and confirm `narrationBecomesTheAnswerBody`
  and the fixture assertion fail. Restore.
- [ ] **Step 7: Update the view.** In the `.answer(let answer, let reply)`
  case:
  - **Body:** `MarkdownText(reply ?? answer.text)`.
  - **When `reply` is set:** add `Text("Summary: \(answer.text)")` in a
    secondary style, `.font(.system(size: transcriptFontSize - 2))`,
    selectable. It goes above the existing telemetry caption, which is
    unchanged.
  - **Preview:** "Answer with summary" uses
    `.answer(EngineAnswer(text: "Six targets: three libraries, one executable, two test targets.", …), reply: "`Package.swift` declares **six targets**:\n\n1. `SwiftStarKit`\n2. `SwiftStarEngine`\n3. `SwiftStarUI`")`.
- [ ] **Step 8: Render every preview in `TranscriptRowView.swift`.** That's
  System, Error, Answer with summary, Rebuilt after rewind and Switched
  model. Look at each. The body comes first, then "Summary: …", then the
  telemetry caption.
- [ ] **Step 9: Run both tiers and commit.** Run `just test` and
  `just integration`, which must both pass. Commit with the message
  `SU.6a Task 1: the 27B reply is the answer's body`.

### Task 2: "Queued" from the engine, and the wording

**Files:**
- Create: `Sources/SwiftStarKit/WindowTitle.swift`
- Modify: `Sources/SwiftStarUI/Session/TranscriptView.swift:17`
- Modify: `Sources/SwiftStarUI/Transcript/PromptBubble.swift:6`, the doc
  comment
- Modify: `Sources/SwiftStarUI/Session/TranscriptRowView.swift:7`, the
  `queued` doc comment
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift:22`
- Modify: `Sources/SwiftStarUI/Session/ComposerView.swift:26`
- Test: `Tests/SwiftStarKitTests/FoundationExtensionTests.swift`

**Interfaces:**
- Produces: `public enum WindowTitle { public static func text(workspace: URL?) -> String }`.
  It returns `workspace?.leafName`, or "SwiftStar" when there's no
  workspace.

- [ ] **Step 1: Write the failing test.** Name it `windowTitle`, with
  arguments `(URL?, String)`:
  - `(nil, "SwiftStar")`
  - `(URL(fileURLWithPath: "/Users/me/projects/swiftstar"), "swiftstar")`
- [ ] **Step 2: Run it and see it fail.** Run
  `swift test --filter FoundationExtensionTests`. Expected: a compile
  failure, because there's no `WindowTitle` yet.
- [ ] **Step 3: Implement `WindowTitle`, and see it pass.** Break check:
  return "Agent" for nil, and confirm the nil row fails. Restore.
- [ ] **Step 4: Make the view changes.**
  - `TranscriptView` passes `transcript.isQueued(rowAt: index)`.
  - Both `queued` doc comments become: "The engine reported this prompt as
    queued."
  - `SessionView` gets
    `.navigationTitle(WindowTitle.text(workspace: controller.workspace))`.
  - The placeholder becomes "Ask about this project…".
  - `queuedMarksPendingRow` (`EngineTranscriptTests.swift:165`) already pins
    that a pending row isn't queued until `.queued` arrives. No new Kit test.
- [ ] **Step 5: Render every preview in the touched files.** Look at each:
  - `TranscriptView`: Running, Empty
  - `PromptBubble`: PromptBubble, PromptBubble queued
  - `SessionView`: Running, Idle, Large font. The previews have no
    workspace, so the title reads "SwiftStar" where the toolbar shows it.
  - `ComposerView`: Ready, Idle, Engine not found. The placeholder reads
    "Ask about this project…".
  - `TranscriptRowView` again, for the comment-only change.
- [ ] **Step 6: Run both tiers and commit.** Run `just test` and
  `just integration`, which must both pass. Commit with the message
  `SU.6a Task 2: Queued only when the engine says so; title and placeholder`.

### Task 3: Indented code, and close

**Files:**
- Modify: `Sources/SwiftStarKit/MarkdownPreprocess.swift`
  - `:6-40`: `deLaTeXed`'s loop and its doc comment
- Test: `Tests/SwiftStarKitTests/MarkdownPreprocessTests.swift`, the
  `codeIsVerbatim` and `prose` tables
- Modify: `ROADMAP.md`
- Modify: `docs/superpowers/plans/2026-10-13-su6a-what-you-read.md`, adding
  `## Result`

**Interfaces:**
- The rule, inside `deLaTeXed`'s loop and checked before the fence test:
  - **Kept verbatim:** a line starting with four spaces or a tab, outside a
    fence.
  - **Condition:** the previous line was blank, the start of the text, or a
    line kept this way.
  - **What keeping does:** it flushes the prose buffer first, then appends
    the line as is.
  - **Blank lines:** they pass through as today, so an indented block with
    blank lines inside it is kept whole.

- [ ] **Step 1: Write the failing tests.**
  - New `codeIsVerbatim` rows, each with a label comment:
    - `"Intro.\n\n    echo $$\n    \\to y"`: two lines of indented code
      after a blank line
    - `"\techo \\to y"`: tab-indented, at the start of the text
    - `"- item\n\n    \\(a\\) stays"`: an indented list paragraph is
      kept raw (Review Focus 5, the accepted trade-off)
  - A new `prose` row, `indentedFenceMarkerOpensNoFence` (Review Focus 4):
    input `"Intro.\n\n    ```\n\nThen $$x$$."` → output
    `"Intro.\n\n    ```\n\nThen x."`.
  - A guard `prose` row, `indentedLazyContinuationIsProse`: input
    `"Text\n    \\(x\\)"` → output `"Text\n    x"`. It already passes;
    it's here for the break check in Step 4.
- [ ] **Step 2: Run them and see them fail.** Run
  `swift test --filter MarkdownPreprocessTests`. Expected:
  - the three new verbatim rows fail, because LaTeX inside them is
    converted
  - `indentedFenceMarkerOpensNoFence` fails, because the indented marker
    opens a fence that keeps `$$x$$`
  - the guard row passes
- [ ] **Step 3: Implement the rule and update the doc comment.** The
  comment adds indented code blocks to "Code is left exactly as written".
- [ ] **Step 4: Run them and see them pass.** Then run the break check:
  drop the "previous line blank or kept" condition, and confirm
  `indentedLazyContinuationIsProse` fails. Restore.
- [ ] **Step 5: Close.**
  - Write `## Result` in this plan: commits, what diverged, the break
    checks.
  - In `ROADMAP.md`:
    - the SU.6 Status gains "6a done", with a link to this plan
    - the punch list loses:
      - "The 27B's two texts"
      - "Queued" from Copy
      - the "agent" wording
      - "4-space indented code" from "Left from SU.5a"
    - Engine requests gains: "`resumed.turns` carries no narration, so a
      rebuilt 27B turn shows only its summary."
  - Run `just lint-docs` and make sure it passes.
- [ ] **Step 6: Run both tiers and commit.** Run `just test` and
  `just integration`, which must both pass. Commit with the message
  `SU.6a Task 3: indented code is left alone; close 6a`.

## Result

**Commits:** `a9b6ea9`..this one, on `main`. Suites: 94 fast and 39
integration, all passing.

**Break checks:** each new test failed against one broken line, then
passed once it was restored.
- **The merge:** always appending fails the merge rows, the mid-turn prompt
  test and the fixture assertion. Comparing texts untrimmed fails
  `equalTextsShowOnce`. Not skipping user rows fails
  `promptBetweenNarrationAndAnswerStaysPending`.
- **The title:** returning "Agent" for no workspace fails `windowTitle`.
- **Indented code:** dropping the after-a-blank-line condition fails
  `indentedLazyContinuationIsProse`.

**Previews:** all of the touched files' previews were rendered and looked
at. The preview window shows the preview's name rather than the session
title, so the title is covered by `WindowTitle`'s test.

**Diverged:**
- The window-title test is its own `WindowTitleTests` suite, in
  `FoundationExtensionTests.swift`.
- `TranscriptRowView`'s comment-only change in Task 2 used Task 1's renders.

**Final review fix:** a fence indented under a list item lost its code. The
4-space marker was kept as indented code instead of opening a fence, so
`echo $$` inside it was de-LaTeXed. Fences are now checked before indented
code (`listItemFenceKeepsItsCode` failed first, then passed). Review Focus 4
flips as a result: a lone indented fence marker now opens a fence, and if
it's never closed the rest stays as written. That's D4's "leave it as
written" direction (`indentedFenceMarkerOpensAFence`).
