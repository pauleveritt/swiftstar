# Pathologies

Ways a small local model has been observed going wrong during agentic tasks
(repair, editing, orchestration), collected from measurement campaigns as they
run. One line each; the capture that shows it is the real evidence, not this
list. Not a roadmap — some of these are model behavior, some are harness bugs
that provoke the behavior; both belong here because either can produce the
same symptom.

What was done about these, and whether it worked, is the companion file:
[`remediations.md`](remediations.md), cross-referenced by the entry numbers
below.

1. **Delivery under-count.** Diagnosed N broken files correctly, emitted fewer
   than N — because the prompt asking it to emit was itself singular ("the
   file you just diagnosed"). Round 2 then re-emits the same one file.
2. **Talk yourself out of the answer.** Correctly diagnosed a bug (e.g. a
   missing `lang="en"`), then reasoned its way out of fixing it and left the
   file untouched — "I don't see any issues with the `<html>` tag."
3. **Blame the wrong cause.** Attributed a test failure to an unrelated,
   plausible-sounding cause (stripped `async` from route handlers) instead of
   the actual defect, and edited a file that was never graded.
4. **Round-2 self-copy.** Given a second repair round, re-emitted a
   byte-identical copy of round 1's (wrong) answer instead of using the
   updated evidence it was handed.
5. **Format collapse.** Emitted a fenced code block with no heading line, so
   the harness's harvest discards it entirely — including, at least once, a
   complete and correct file.
6. **Generation-repetition exhaustion.** Got stuck in a repeated-text loop and
   burned the token budget before it ever reached the file it had correctly
   diagnosed.
7. **Placeholder tool-call syntax.** Emitted its own system-prompt template
   text as a literal tool call — `"name": "{function-name}"` — instead of a
   real one.
8. **Tool call inside `<think>`.** Emitted a tool call before finishing a
   reasoning block; the engine rejects it, and three in a row kills the turn
   even after the engine's own corrective nudge.
9. **Deadlock on an underspecified instruction.** Given a directive that named
   an action ("dispatch each phase once") without saying whether it meant
   count or order, spent an entire turn — visibly, in text — relitigating
   which reading was intended, and took no action at all.
10. **Silent framework substitution.** Left without an explicit framework
    pin in context, built the same app in a different framework than
    intended (Flask instead of the specified FastAPI) — passing its own
    validation but failing the acceptance suite's import at collection time,
    a total loss rather than a partial one.
11. **~~Repeated output during a tool call.~~ NOT A MODEL PATHOLOGY — engine
    false positive.** Recorded here first as model repetition, then traced to
    the engine: `agent_dsml_tail_is_degenerate` (`ds4_agent.c:2726`) aborts a
    tool call when the tail is a repeated unit spanning >=64 bytes. A **64-dash
    comment separator** — `# ----...`, ordinary Python section formatting — is
    exactly 64 bytes and trips it. Measured: every one of 5 consecutive voided
    cells ended on a dash run of exactly 64. The guard's own comment
    anticipates the class ("a 30-dash rule survives") but picked a threshold
    that real 64/72/80-column separators exceed. Kept in this list as a
    caution: a "model pathology" that reproduces perfectly can still be the
    harness or engine — check the tooling before writing it down as behavior.

12. **Content trap, repeated.** Reused a known-bad pattern
    (`default_factory=datetime.now` for a field documented as needing a
    timezone) even with the failing assertion in hand, across two rounds.
13. **Edit the oracle, not the code.** Instead of fixing the underlying bug,
    modified the test file itself to match the buggy behavior — the assertion
    then passed for the wrong reason, and the actually-graded suite never ran
    it. Seen twice: expecting a 307 instead of fixing a 303 redirect, and a
    round-2 edit to `tests/test_app.py` instead of `app.py`.
14. **Assertion-polarity regression.** Given a failing assertion, misread
    which direction it wanted and "fixed" already-closer-to-correct code into
    something actively worse — turned `field(default_factory=datetime.now)`
    into `datetime = datetime.now()`, dropping the factory entirely — which
    then failed a *different*, unrelated assertion than the original bug.
15. **Graded-the-wrong-duplicate.** NOT A MODEL PATHOLOGY — harness bug, like
    11. When a turn contains multiple self-corrected attempts at the same
    file heading, the harvest kept the *first* occurrence rather than the
    model's own final corrected version, so a model that caught and fixed its
    own mistake mid-turn still failed the round.
16. **Think-to-the-wall.** Given a reasoning-inducing system prompt with
    unbounded `--think`, filled 97% of a 16,384-token context (15,873 tokens
    across 7 rounds) with reasoning and never produced an answer. Confirmed
    prompt-induced rather than flag-induced: the same model and flag produced
    0% and 80% thinking on two different prompts.
17. **Instruction override of a false directive.** Given a repair directive
    asserting "exactly one file is wrong" that was actually false (5 of 6
    writable files didn't exist), correctly derived the real multi-file fix,
    then explicitly talked itself back out of it three times by quoting the
    false directive verbatim ("However, the instructions say to emit only one
    file...") before committing to emit just one. Distinct from 2: here the
    reasoning is correct *first*, and it's a quoted false premise that walks
    it back, not unprompted self-doubt.
18. **Wrong-side assignment on a traceback.** Given a NameError-style
    traceback naming an undefined identifier, reasoned correctly in prose
    about the fix needed ("we need to add a `complaints` variable") but then
    defined a *different*, wrongly-named variable (`SEED_COMPLAINTS` instead
    of `complaints`) — invented a left-hand side instead of fixing the
    right-hand side the traceback actually named.
19. **Locate-only stall.** Without an explicit file locus handed to it up
    front, burned an entire turn (up to 62 consecutive calls) issuing only
    read/list/search tool calls with zero mutations, never reaching any edit
    — ended only by a user interrupt. Real-app turns stalled this way 4/6
    (67%) of the time vs. 12% in a file-list-primed harness.
20. **Redundant re-locate.** Within a single turn, issued the identical
    (tool, path) call repeatedly with no new information gained between
    calls — up to 347 consecutive rereads of the same file. Pure wasted
    prefill, distinct from 6's output-token repetition.

---

*Provenance: entries 1–9 and 12 come from the 2026-08-28/29 Mellum fixture
campaign (Block B, the plural-fix arm, and the depth-3 estimation arm); 10 and
11 from the orchestrate-loop generalization arms on `roadmap-user-story`.
Entry 11 is kept despite being an engine bug rather than a model behavior —
misfiling it was the mistake worth remembering. Entries 13–20 come from the
2026-08-26/28/29 research notes under `docs/superpowers/research/`
(`overnight-80-cell-verdict`, `failure-classification`,
`block-b-negative-result-analysis`, `block-c-capture-mining`,
`p23-wire-control-research`) and `ROADMAP.md`'s Backlog. Entry 15 is kept
despite being a harness bug for the same reason as 11.*

## Seen in local-ai-pi

A separate, earlier measurement harness (`local-ai-pi`), running
`gemma-4-12B` and `qwen3.6-27B` against its own repair/authoring tasks rather
than ds4/Mellum. Kept here rather than duplicated because the failure modes
travel across harnesses.

21. **No-op edit loop, reported as success.** NOT A MODEL PATHOLOGY — harness
    bug. The mutation engine accepted an edit whose `oldText` equaled
    `newText`, silently writing the same bytes back and reporting
    "changed lines=0" as success. One run looped rereading a 29KB file and
    proposing byte-identical no-op edits until the wall clock killed it with
    zero files written — logged at the time as a model failure.
22. **Near-miss file targeting.** Asked to edit `src/svcs/_autowire.py`,
    wrote a clean, complete file to `src/svcs/autowire.py` instead — a
    plausible sibling name, not the real target — then ran out of its turn
    budget still trying to wire `__init__.py` to the wrong file it had
    created.
23. **Schema-mismatched call repetition.** Repeated a structurally invalid
    edit call — one that contained the correct fix, but with `path` nested
    inside the edit entry instead of at the top level — 49 times
    byte-identically, always failing schema validation, without ever
    adapting the call shape. A separate task showed the same shape: 46
    guard-blocked repeats of an anchor-mismatched retry starting at call 14
    of 60.
24. **Destructive failure tied to task shape.** On one specific task, failing
    runs didn't just fail to add code — they reliably deleted existing
    tests. A 24-replicate noise-floor run showed 5/6 "tests-vanished" plus 1
    "damaged" (0/6 accepted); a separate guard-mechanism run on the same task
    also ended "tests-vanished, delta -30, 101 nodes missing." Recurred
    across independent experiments, suggesting a failure signature tied to
    this task/edit shape rather than a one-off.
25. **Empty-workspace probing spiral.** Given an empty workspace with no
    explicit statement that it was empty, repeatedly re-checked with `ls -R`
    — 245 repetitions in one run, contributing to a 261-turn run with a
    71.88 MB transcript. Stating the empty workspace as a fact in the prompt
    collapsed this to 1 repetition.
26. **Headless conversational stall.** In a single-shot, non-interactive
    agentic run, 16/16 replicates took exactly one turn, made zero tool
    calls, correctly and accurately restated the task requirements, and then
    stopped with "Please let me know which file I should start with..." —
    treating a one-shot execution context as an interactive chat awaiting a
    reply that will never come. Distinct from 9: the spec here was verified
    unambiguous, and there was no relitigation loop, just a single clean
    stop-and-ask.
27. **Operationally vague self-authored specs.** When used to author a task
    contract rather than execute one, drafts passed every structural/coverage
    check (8/8) but were behaviorally complete and operationally vague — e.g.
    "register the resulting context for cleanup" where a hand-written
    contract says the concrete `append (name, svc) to self._on_close`.
    Contracts authored this way were ~2.5x shorter, had almost no code
    fences, and led executors to a correctness drop (4/4 hand-authored vs.
    1/4 model-authored on oracle checks).
28. **Scope overreach via its own contract's prose.** Given a handoff
    contract restricted to `src/svcs/**`, produced a functionally perfect
    patch (3/3 identical, oracle 19/19 every time) but also edited
    `docs/integrations/flask.md` because the contract's own "Documentation
    Note" section asked for a docs update — outside the writable-file policy.
    Treated every instruction inside the contract as in-scope, including one
    the contract's own policy excluded.

*Provenance: entries 21–28 come from `local-ai-pi`'s own commit history and
research notes (`d758a03`, `604884b`, `2026-08-10-phase7-frontier-contracts-variance.md`,
`7ca49cb`, `9e2c624`, `2026-08-04-phase5-cycle10-publishable-arm.md`,
`2026-08-04-phase5-cycle4-user-story-arms.md`, `docs/engine/shootout.md`,
`8da2576`, `db33752`). Entry 21 is kept despite being a harness bug for the
same reason as 11.*
