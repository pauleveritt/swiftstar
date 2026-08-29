# Pathologies

Ways a small local model has been observed going wrong during agentic tasks
(repair, editing, orchestration), collected from measurement campaigns as they
run. One line each; the capture that shows it is the real evidence, not this
list. Not a roadmap — some of these are model behavior, some are harness bugs
that provoke the behavior; both belong here because either can produce the
same symptom.

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

---

*Provenance: entries 1–9 and 12 come from the 2026-08-28/29 Mellum fixture
campaign (Block B, the plural-fix arm, and the depth-3 estimation arm); 10 and
11 from the orchestrate-loop generalization arms on `roadmap-user-story`.
Entry 11 is kept despite being an engine bug rather than a model behavior —
misfiling it was the mistake worth remembering.*
