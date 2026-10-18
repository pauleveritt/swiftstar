# SwiftStar AN.3 design: remedies

Date: 2026-10-18. Status: **written, awaiting the owner's acceptance.** The
owner chose option 1 on 2026-10-18: the analysis model proposes, the owner
picks, and SwiftStar applies after Done. How a remedy is applied wasn't
chosen, so D4 takes (a) and keeps (b) as the alternative.

## Goal

An Analyze ends with remedies the owner can take. The remedies are lines
for the project's instructions file (`AGENTS.md`, else `CLAUDE.md`), which
the engine reads into every session's first turn (ds4-engine TUI.48).

## What exists

- **The fork.** Analyze resumes the session as a fork and asks its model
  about the report. The instruction ends: "Then propose remedies. Don't
  edit files." (`EngineAnalysis.swift:41-44`). Done sends `/resume <main>`,
  and the main session comes back as it was (AN.2). Today the proposals are
  prose in the answer, and nothing acts on them.
- **The engine's own suggestions.** The report has `suggestions[] {rule,
  file, diff, why, evidence_prompts}`, each a one-line `+- …` addition to
  `AGENTS.md` (`session_report.py`, rules `test-command` and `re-read`).
  Across the owner's 38 latest sessions there were **none** (checked
  2026-10-18, `report --json` on each). They count, but they can't be the
  whole of it.
- **How the engine reads instructions.** It reads `AGENTS.md`, else
  `CLAUDE.md`, from the **committed** copy, and names an uncommitted one in
  its `project_instructions` event (`project_instructions.py:116-131`). So a
  remedy takes effect once it's committed.

## Decisions

- **D1. The fork's model proposes lines in a fixed form.** The analysis
  instruction asks for remedies as a fenced block tagged `agents-md`, one
  proposed line per line. SwiftStar finds the last such block in the
  fork's rows, in an answer or a narration. A follow-up question can
  replace the block. With no block, there are no model remedies, and the
  prose stays as it is.
- **D2. The engine's suggestions join the list.** Each `suggestions[]`
  entry from the report Analyze used gives its `diff` line, without the
  leading `+`, marked "from the engine's report" with its `why`.
- **D3. A Remedies card in the fork, one checkbox each.**
  - It sits under the answer that holds the block, and starts unticked.
  - A line already in the instructions file shows "already there" and
    can't be ticked.
  - The Done banner reads "Done · add N lines to AGENTS.md" while any are
    ticked.
- **D4. Applying is SwiftStar's edit to the checkout, after Done (a).**
  - **When:** once the main session is back at `input`, SwiftStar appends
    the ticked lines to the checkout's `AGENTS.md`.
  - **Which file:** `AGENTS.md`, else `CLAUDE.md` if only that exists, else
    a new `AGENTS.md`.
  - **How:** under a `## From Analyze` heading added once, with lines
    already there skipped.
  - **What it says:** a system row such as "Added 2 lines to AGENTS.md.
    The engine reads the committed copy, so commit it to take effect."
  - **Nothing is sent to the model.**
  - **The alternative (b),** if the owner prefers: after Done, send the
    lines as a prompt to the main session ("Add these lines to AGENTS.md:
    …"). The engine edits its candidate, and the change reaches the
    checkout with `ds4-dogfood apply`. That costs one model turn and goes
    through the engine's review path.
- **D5. Kit owns the rules.**
  - `Remedies.parse(rows:from:)`: the block, in rows after the fork's first
    row.
  - `Remedies.merged(model:engine:existing:)`: the list, deduplicated.
  - `Remedies.applied(to:lines:)`: the new file text.

  The file read and write are the controller's, in the checkout only.
- **D6. Nothing is applied without Done.** Leaving the fork any other way
  applies nothing. That covers a failed return, a quit and a project
  switch.

## Testing

- **Fast tier (Kit):**
  - `parse`: no block; one block; two blocks, where the last wins; a block
    in narration; a block before the fork's first row, ignored.
  - `merged`: engine and model lines, a duplicate, and one already in the
    file.
  - `applied`: an empty file, an existing file with the heading added once,
    and `CLAUDE.md` chosen when only it exists.
  - The banner's label with 0 and with 2 ticked.

  Each is shown to fail with its behavior broken.
- **Integration.** Over the fake engine:
  - Analyze, then a fork answer with an `agents-md` block, then tick, then
    Done: the temp repository's `AGENTS.md` has the lines, and the
    resumed-session row says so.
  - The same without Done (quit) leaves the file untouched.

  The fork answer comes from a new hand-written fixture beside
  `resumed-answered.ndjson`.
- **Previews:** rendered:
  - the Remedies card, with ticked, unticked and "already there" lines
  - the banner's label
- **Live, on the owner's GPU go:** one Analyze on the 27B, to see whether
  it writes the block.

## Done when

- D1–D6 are built, both tiers are green, and the previews have been looked
  at.
- The live check is run, or deferred by the owner.
- ROADMAP and CHANGELOG are updated.

## Risks

- **The 27B may not write the block.** The live check shows it. If it
  doesn't, the instruction gets an example, or D1 falls back to the
  engine's suggestions only.
- **A remedy can be wrong.** Nothing is ticked by default, each line is
  read before it's taken, and the row after Done says it's uncommitted, so
  `git diff` shows it.
- **The owner hasn't clicked through AN.2 yet.** AN.3 builds on it. The
  integration test covers its path, but not how it feels to use.
