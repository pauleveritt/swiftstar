# Changelog

What changed for someone using SwiftStar. Each entry names its roadmap
cycle; the cycle's plan in `docs/superpowers/plans/` has the detail.

## Unreleased

### The prompt field

- Liquid Glass prompt field and Send/Stop button (SU.6e)
- Analyze mode tints the prompt field (SU.6e)
- ↑/↓ recalls earlier prompts (SU.8)
- `@` file picker in the prompt field (SU.14)
- A line under each prompt shows the files it attached, and in red the
  ones it couldn't (SU.14)
- Esc closes the `@` picker only until you type a different word (SU.17)
- The `@` picker leaves out links to big or missing files (SU.17)

### Text and layout

- One font size for the whole window, 5 steps, 18 pt default (SU.9)
- View › Bigger, Smaller, Actual Size (⌘+, ⌘−, ⌘0) (SU.6f)
- The transcript scrolls under the prompt field and fades (SU.6f)
- Smaller sidebar text (SU.6f)
- Window minimum 1000 pt, which fixes a crash in narrow windows (SU.11)
- Numbers follow your locale (SU.6g)

### The transcript

- Tool cards color code by the file's language; Markdown as colored raw
  text (SU.15)
- Wide tables scroll sideways, with a scroller while scrolling (SU.13)
- Code in list items and quotes keeps its `$` and backslashes (SU.17)
- Analyze drops a report that arrives after the session moved on; one that
  can't start the fork says the main session is unchanged (SU.17)
- Analyze's report comes from ds4-engine (`ds4-dogfood report`), with the
  engine's own labels next to its figures, such as "short batch, fixed
  cost" (AN.4)

### Status bar and inspector

- Steady prefill / generation numbers, explained in a tooltip (SU.10)
- GPU memory shown against the engine's plan, in GiB (SU.6g)
- The GPU limit is the inspector's last row, explained (SU.6g)
- Inspector: the sidebar's type size, values in one font (SU.11)
- Inspector: long values wrap under their labels (SU.9)
- Inspector: a fixed width, no splitter (SU.11)
- A "Session averages" card in the inspector (SU.6g)

### Toolbar, sidebar and menus

- Toolbar menus show an icon with their value (SU.11)
- The window is titled by the conversation (SU.11)
- The running conversation is listed and selected in the sidebar (SU.11)
- "New Conversation" is the sidebar's first row (SU.11)
- File › New Conversation (⌘N) (SU.11)
- Resume asked mid-turn resumes the conversation you clicked (SU.17)
- After resuming an earlier session two branches share, the sidebar
  selects the right one (SU.17)

### Under the hood

- The model list loads promptly when the engine is slow to answer (SU.6g)
- A folder deep inside a repository works as the workspace (SU.17)
- An engine that sends bad output is stopped, by force if it must be (SU.17)
- A missing engine command is named in its note (SU.17)
- The prefix-cache fill time follows your locale (SU.17)
