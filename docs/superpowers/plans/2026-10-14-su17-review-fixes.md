# SU.17: the review's fixes

A plan for an external review of `main` at `6f1eac0` (2026-10-14), brought
by the owner: nine correctness findings (P2), smaller defects, dead code
and stale docs. Each finding below was checked against the code before
planning; each fix starts with a test that fails on today's code.

## Decisions

**D1. Do all nine P2 findings,** in the review's terms:

| # | Finding | Fix |
|---|---|---|
| 1 | A delayed Analyze report acts on a replacement session | capture the session's identity and turn count; drop a stale success or failure |
| 2 | Resuming a shared ancestor selects the wrong conversation | the first checkpoint's directory replaces the resumed-from id |
| 3 | Deep folders pass validation but `ProjectRoot` stops at 5 | one unbounded walk for both |
| 4 | A protocol error sends one SIGTERM, no escalation | reuse the bounded shutdown, keeping the protocol diagnosis |
| 5 | Esc hides a picker query forever | a changed query clears the dismissal |
| 6 | Sidebar Resume reads state the dismissal clears | capture the presented conversation |
| 7 | Cleanup corrupts fenced code on a list or quote line | container markers stripped before fence and indent checks |
| 8 | The lister measures a symlink, not its target | stat the target; a dangling link is left out |
| 9 | A quit at its safety bound leaves analysis mid-transition | abandon the transition, with the main-unchanged notice |

**D2. And the smaller items:** fixture controllers persist nothing; the
JSON command's missing-command message names the command; the recorder
cleans up on exceptions and closes its pipes; the runner test kills its
grandchild; the prefix-cache line's duration takes the locale.

**D3. Cuts:** the unused `.headline` role; the empty `MarkdownText`
extension; `statusText`; write-only report fields; the duplicated analysis
test setup; `MetricsFormattingTests`' dispatcher split into per-function
tables; `BRIEF.md` refreshed (sessions, targets, model switching).

**D4. The review's two missed ideas:** the gallery gets fixture files so
the `@` picker works there; and a shrinking-history test after a rewind.

**Kept, as the review advises:** the Markdown measurement cache, the pipe
readers, the tooltip bridge, the shared commands, the inline sidebar rows.

## Tasks

Each task: tests first, shown failing; then the fix; `just test`.

1. **UI state (5, 6):** `ComposerView`, `ConversationList`; Kit helpers
   where a test can reach the rule.
2. **Files (3, 8):** `ProjectRoot`, `WorkspaceChoice`, `WorkspaceFileLister`;
   Kit and integration tests (deep folder; valid, oversized-target and
   dangling links).
3. **Session identity (2):** `EngineSessionModel`; its tests, incl. the
   branched B → M, C → M case.
4. **Analysis (1, 9):** `EngineController.analyze`, `relaunch`,
   `EngineSessionModel`; integration tests with a delayed report loader
   and a quit that hits its bound.
5. **Process (4):** `EngineSession`; an integration test with a fake that
   ignores SIGTERM after bad output.
6. **Markdown (7):** `MarkdownPreprocess`; list and quote container cases.
7. **Small items (D2)** and **the missed ideas (D4).**
8. **Cuts and docs (D3).**
9. **Close:** `ROADMAP.md`, `CHANGELOG.md`, `## Result`, both tiers.
