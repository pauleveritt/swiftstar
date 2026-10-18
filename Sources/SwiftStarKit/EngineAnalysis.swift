import Foundation

/// An analysis of the session (AN.2): the main session is resumed as a fork,
/// the report is asked about there, and Done resumes the main session again,
/// so its context comes back without the analysis.
public struct EngineAnalysis: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        /// The fork is starting; `report` waits for its first `input`.
        case forking(main: URL, report: String)
        /// In the fork. `firstRow` is where the analysis's own rows begin.
        case analyzing(main: URL, firstRow: Int, report: String, promptSent: Bool)
        /// Done was sent; the main session is being resumed. The fork's rows
        /// are kept in case the engine refuses (`analyzing` again).
        case returning(main: URL, firstRow: Int, report: String)
    }

    public var stage: Stage

    public var main: URL {
        switch stage {
        case .forking(let main, _), .analyzing(let main, _, _, _), .returning(let main, _, _): main
        }
    }

    /// Said when the fork or the return fails: the main session is untouched.
    public static func mainUnchanged(_ main: URL) -> String {
        "The main session \(main.lastPathComponent) is unchanged. Resume it with: "
            + "ds4-dogfood tui --resume \(main.lastPathComponent)"
    }

    /// Where the analysis's rows begin, once the fork is up.
    public var firstRow: Int? {
        if case .analyzing(_, let firstRow, _, _) = stage { firstRow } else { nil }
    }

    public static let forkingNotice = "Starting analysis…"
    public static let forkDivider = "Analysis — a copy of this session"
    public static let promptShown = "Analyze the session report above"
    public static let banner = "Analyzing a copy — Done returns to the session as it was"
    public static let composerPlaceholder = "Ask about the analysis…"
    /// AN.3, D7: the wording the 27B answered with a block on 2026-10-18.
    /// Without "from the report alone, without tools" it explored the
    /// repository instead, and ran out of context with no answer.
    public static let instruction = """
        Explain each flagged step: what the model was trying to do, and why it \
        failed or was wasted. Then propose remedies: lines to add to this \
        project's AGENTS.md that would prevent them, in one fenced code block \
        tagged \(Remedies.tag), one line per remedy. Answer from the report \
        alone, without tools.
        """

    public static func returnDivider(prompts: Int) -> String {
        "Analysis ended — back at prompt \(prompts)"
    }

    /// What the fork's model is asked: the report, then the instruction.
    public static func prompt(report: String) -> String {
        "\(report)\n\n\(instruction)"
    }
}
