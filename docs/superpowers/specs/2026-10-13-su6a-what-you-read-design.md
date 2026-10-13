# SU.6a: what you read

Part of SU.6's punch list (`ROADMAP.md`). This part covers what the
transcript says and how it reads. Engine information (6b) and remembering
(6c) come later; the Markdown renderer was settled in
[6d](../plans/2026-10-13-su6d-markdown-renderer.md).

## Decisions

The owner settled these on 2026-10-13.

**D1. The 27B's reply is the answer body, with its summary under it.** On
the 27B, `narration` is the full Markdown reply and `answer` is `finish`'s
one-line summary (EN.1 D4, confirmed by its recordings). Today the full reply
reads as a preamble and the one-liner as the answer. Instead, the reply
becomes the answer's body, and the summary sits under it as a secondary
"Summary: …" line, above the telemetry line.

**D2. The window is titled by the workspace folder; the composer asks about
the project.** "Agent" and "Ask the agent…" are left over from before P28.
The title becomes the workspace folder's name, with "SwiftStar" as the
fallback. The placeholder becomes "Ask about this project…". This is a small
step toward SU.7's project-as-identity, without building it.

**D3. "Queued" shows only for prompts the engine reported as queued.** This
item comes from the punch list, so no new decision was needed.

**D4. Indented code is protected the conservative way.** This item comes
from the punch list too. When unsure, leave text as written: a formula left
unconverted is a smaller fault than corrupted code.

## 1. Narration and answer (D1)

**Where:** `EngineTranscript` (Kit), when it folds `.answer`.

- **The rule.** When an answer with text arrives, look at the latest row
  that isn't a user prompt. If it's a `.narration`, that row becomes the
  answer row at the same index.
  - A prompt sent mid-turn can land between the two. It stays after the
    answer, and because no row moves, the pending and queued row indices
    stay valid.
  - It's the same in-place update a tool card already gets.
  - The invariant comment at `EngineTranscript.swift:88` changes to: rows
    are never removed or reordered, and a narration row may absorb its
    turn's answer.
- **The row.** `TranscriptRow.answer` carries the absorbed narration as
  `reply: String?`.
  - **With a reply:** the body is the reply, and the engine's text shows
    under it as "Summary: …".
  - **Without one:** the body is the answer's text, as today.
- **Equal texts.** If the trimmed narration equals the trimmed answer, the
  row shows the text once, with no summary line. This covers EN.1 §2.4's
  dedupe, which its recordings never needed.
- **No merge when:**
  - anything else sits between them (a tool card, thinking, system or
    error row)
  - the answer has no text: the "No answer: …" error row and the narration
    stay as today
- **Not affected:** a transcript rebuilt from `resumed`. Its turns carry
  only `answer`, so a resumed 27B turn shows just the summary. That needs
  the engine (§5).
- **View.** In `TranscriptRowView`'s `.answer` case:
  - the body uses `MarkdownText`
  - the summary is a selectable secondary `Text`
  - the telemetry caption is unchanged

## 2. "Queued" (D3)

`TranscriptView.swift:17` passes `transcript.isQueued(rowAt:)` instead of
`isPending(rowAt:)`. Today "Queued" shows from the moment of sending.
`PromptBubble.queued`'s doc comment changes to: the engine reported this
prompt as queued. A row that is pending but not yet acknowledged shows no
label; that state lasts only until the engine replies.

## 3. Wording (D2)

- `SessionView.swift:22`: `.navigationTitle` becomes the controller's
  `workspace?.leafName`, or "SwiftStar" when there is no workspace.
- `ComposerView.swift:26`: the placeholder becomes "Ask about this project…".

## 4. Indented code (D4)

`MarkdownPreprocess.deLaTeXed` leaves a line verbatim when:
- it's indented four or more spaces, or starts with a tab, and
- it follows a blank line, or another line kept this way.

A line indented that much straight after paragraph text is a lazy
continuation in CommonMark, so it's still de-LaTeXed. The known trade-off:
an indented paragraph inside a list item is also kept raw.

## 5. Record

- **Backlog, engine requests:** `resumed.turns` carries no narration, so a
  rebuilt 27B turn shows only its summary.
- **ROADMAP:** the 6a punch-list items move out when this closes.

## Testing

**Fast tier** (`EngineTranscriptTests`, `MarkdownPreprocessTests`). Each
test is shown to fail first.
- The 27B `tool-read` fixture's turn ends in one answer row that has both
  texts, and no narration row.
- Equal narration and answer give one row with no reply.
- A tool card between them blocks the merge.
- An empty answer keeps the narration row and adds the error row.
- A prompt sent between the narration and the answer stays pending at its
  index, and the narration still merges.
- New verbatim rows: indented code after a blank line, with a tab, and as
  two lines in a row.
- A prose row: a lazy continuation is still de-LaTeXed.

**Previews**, rendered and looked at:
- `TranscriptRowView`'s "Answer with summary", changed to a 27B-shaped row
  with a reply
- `PromptBubble` and "PromptBubble queued"
- the `SessionView` and `ComposerView` previews

Both tiers (`just test`, `just integration`) pass.

## Out of scope

- Engine information (6b) and remembering (6c).
- The window's project identity beyond its title (SU.7).
- Restoring narration on resume, which waits on the engine (§5).
