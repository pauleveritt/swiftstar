import Foundation

/// P20 (D3): the orchestrate directive — the prompt that turns a
/// `/orchestrate` command into the model-driven coordination loop. Pure text;
/// the fast tier asserts the required clauses are present. The loop is
/// model-driven (D1): the model decomposes, dispatches via the `dispatch`
/// tool, reads receipts, validates, and writes files. One-shot-first (D2):
/// dispatch each phase once and do the work yourself on a refusal — the host
/// never runs a repair loop.
public enum OrchestrateDirective {
    public static func build(task: String, writableFiles: [String]) -> String {
        // D5: `--files` is scope context, not enforcement — the per-dispatch
        // `writableFiles` (revision-checked host-side) is the real boundary.
        let scope = writableFiles.isEmpty
            ? "the whole workspace"
            : writableFiles.joined(separator: ", ")

        let lines = [
            "You are in orchestrate mode: run a multi-phase task end to end, then write",
            "the result.",
            "",
            "Work in this order:",
            "1. Decompose the task into phases. Each phase is a bounded unit of work with",
            "   a machine-checkable acceptance criterion (a command whose exit status",
            "   decides pass/fail).",
            "2. For each phase, dispatch it to a subagent with the `dispatch` tool, giving",
            "   these parameters: `taskText` (the phase's objective),",
            "   `writableFiles` (a comma-separated list of the files that phase may",
            "   touch), and `validationCommand` (the command you will run to check the",
            "   phase; optional).",
            "3. A dispatch returns a receipt: a candidate ref on success, or a typed",
            "   refusal (refusedTool / budgetExceeded / validationFailed / noChanges).",
            "   Read the receipt.",
            "4. One-shot-first: dispatch each phase once. If a phase's receipt is a",
            "   refusal, do the phase's work yourself in the workspace instead of",
            "   re-dispatching. Re-dispatch at most once, and only with a corrected",
            "   packet.",
            "5. Integrate the phases and validate the whole result with the validation",
            "   command. Do not claim success unless the command exits 0.",
            "6. Never dispatch an open-ended exploration or a watched interactive turn",
            "   that has no acceptance predicate — do that work yourself.",
            "",
            "Writable scope for this task: \(scope).",
            "",
            "Task: \(task)",
        ]
        return lines.joined(separator: "\n")
    }
}

/// P20 (D4): the dispatch-preference rule — an always-on system-prompt clause
/// governing when the agent prefers `dispatch`. Prompt-only: no app state, no
/// Settings toggle, no wire field. The "never for watched interactive" clause
/// is the 2026-08-27 1809 capture's negative data point, encoded.
public enum DispatchPreferenceRule {
    public static let text = "Dispatch preference: when a piece of work has a machine-checkable acceptance predicate and an exact writable-file set, prefer dispatching it to a subagent via the `dispatch` tool rather than doing it inline. Do not dispatch a watched interactive turn or an open-ended exploration with no acceptance predicate — do that work yourself. After a few rounds of exploration, stop exploring and either dispatch the work with a concrete acceptance contract or do it directly."
}
