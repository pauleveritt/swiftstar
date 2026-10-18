import Foundation

public struct EngineToolCard: Equatable, Sendable {
    public var tool: EngineTool
    public var ok: Bool?
    public var durationMs: Double?
    public var result: EngineToolResult?
    /// Set when the engine declined the call before running it.
    public var rejection: EngineToolRejection?

    public init(
        tool: EngineTool, ok: Bool? = nil, durationMs: Double? = nil,
        result: EngineToolResult? = nil, rejection: EngineToolRejection? = nil
    ) {
        self.tool = tool
        self.ok = ok
        self.durationMs = durationMs
        self.result = result
        self.rejection = rejection
    }

    /// `op path`, or just `op` when the tool has no path; "a call" for a
    /// declined call the engine stopped before its name; "bash" for a `run`
    /// that fell back to bash (SU.18).
    public var headerText: String {
        if isBashRun { return "bash" }
        let op = tool.op.isEmpty && rejection != nil ? "a call" : tool.op
        if let path = tool.path, !path.isEmpty {
            return "\(op) \(path)"
        }
        return op
    }

    /// A `run` with no path: under `--allow-bash`, the call the engine ran as
    /// `bash -c` in its sandbox (SU.18, D2, D6). Its command isn't on the
    /// wire (ds4-engine#260).
    public var isBashRun: Bool {
        rejection == nil && tool.op == "run" && (tool.path ?? "").isEmpty
    }

    /// A bash run's exit and time, from its result's first line
    /// (`run_tool.py:119-124`); nil until the result arrives.
    public var bashRun: BashRun? {
        guard isBashRun, let first = result?.preview.split(separator: "\n").first.map(String.init) else { return nil }
        return BashRun(header: first)
    }

    /// The facts line is red: the call failed, or a bash run exited non-zero
    /// or hit its limit, which the engine still reports as ok.
    public var failed: Bool {
        if ok == false { return true }
        guard let run = bashRun else { return false }
        return run.timedOut || (run.exit ?? 0) != 0
    }

    /// State and duration: `running`, or `succeeded`/`failed` with the time;
    /// `declined` with the reason for a call the engine refused. A bash run
    /// says so, with its exit and time as the engine wrote them.
    public var metadataLine: String {
        if let rejection { return "declined · \(rejection.label)" }
        if isBashRun {
            let ran = "ran as bash in the sandbox"
            guard ok != nil else { return "\(ran) · running" }
            guard let run = bashRun else { return ok == false ? "\(ran) · failed" : ran }
            if run.timedOut { return "\(ran) · stopped at the 120 s limit" }
            return [ran, run.exit.map { "exit \($0)" }, run.seconds.map { "\($0) s" }]
                .compactMap { $0 }.joined(separator: " · ")
        }
        var parts: [String] = []
        switch ok {
        case nil: parts.append("running")
        case true?: parts.append("succeeded")
        case false?: parts.append("failed")
        }
        if let ms = durationMs, ms.isFinite, ms >= 0 {
            parts.append(MetricsFormatting.duration(seconds: ms / 1000))
        }
        if let line = testRunLine { parts.append(line) }
        return parts.joined(separator: " · ")
    }

    /// A `test` result's first line, without its brackets: which Python ran
    /// pytest, its exit code and time (ds4-engine `test_tool.py:113-126`).
    private var testRunLine: String? {
        guard tool.op == "test", let first = result?.preview.split(separator: "\n").first,
              first.hasPrefix("["), first.hasSuffix("]") else { return nil }
        return String(first.dropFirst().dropLast())
    }

    /// The highlight.js language for the result: `diff` for `git`, whose
    /// results are mostly diffs and logs; else the file's (SU.15).
    public var resultLanguage: String? {
        if tool.op == "git" { return "diff" }
        return tool.path.flatMap(CodeLanguage.forPath)
    }

    /// SF Symbol name for the tool's op.
    public var icon: String {
        if rejection != nil { return "xmark.circle" }
        if isBashRun { return "terminal" }
        switch tool.op {
        case "bash", "bash_status", "bash_stop": return "terminal"
        case "write": return "doc.badge.plus"
        case "edit": return "square.and.pencil"
        case "ls": return "folder"
        case "read", "more": return "doc.text.magnifyingglass"
        case "grep": return "magnifyingglass"
        case "git": return "arrow.triangle.branch"
        case "test": return "checkmark.seal"
        default: return "wrench.and.screwdriver"
        }
    }
}

/// A bash run's header line, read as written: `[exit 1 in 2.3 s]`, or
/// `[stopped after 120 s, the time limit]` (ds4-engine `run_tool.py:119-124`).
public struct BashRun: Equatable, Sendable {
    public let exit: Int?
    /// The engine's seconds, as text ("2.3"): shown as sent.
    public let seconds: String?
    public let timedOut: Bool

    public init(exit: Int?, seconds: String?, timedOut: Bool) {
        self.exit = exit
        self.seconds = seconds
        self.timedOut = timedOut
    }

    /// Nil for a line in neither form.
    init?(header: String) {
        if header.hasPrefix("[stopped after "), header.hasSuffix("the time limit]") {
            self.init(exit: nil, seconds: nil, timedOut: true)
        } else if let m = header.firstMatch(of: /^\[exit (-?\d+) in ([\d.]+) s\]$/) {
            self.init(exit: Int(m.1), seconds: String(m.2), timedOut: false)
        } else {
            return nil
        }
    }
}

public enum TranscriptRow: Equatable, Sendable {
    case user(String)
    case narration(String)
    case thinking(String)
    case tool(EngineToolCard)
    /// `reply` is the narration this answer absorbed: on the 27B the full
    /// reply, while the answer's own text is `finish`'s summary (SU.6a).
    case answer(EngineAnswer, reply: String? = nil)
    case system(String)
    case error(String)
    /// Marks where a relaunch rebuilt the transcript.
    case divider(String)
    /// A session report (AN.2), Markdown, shown as a card.
    case report(String)
    /// What a prompt's `@` mentions attached and missed, under it (SU.14).
    case mentions(attached: [String], missing: [String])
}

/// Pure fold of `EngineEvent`s into transcript rows and busy flags.
///
/// Invariant: rows are never removed or reordered (a narration row may
/// absorb its turn's answer in place), which the index-based
/// `pendingUserRows`/`queuedUserRows` rely on — except
/// `rebuild(from:divider:)`, which replaces every row and clears both sets.
public struct EngineTranscript: Equatable, Sendable {
    public private(set) var rows: [TranscriptRow] = []
    public private(set) var isBusy = false
    public private(set) var isGenerating = false
    public private(set) var isAwaitingInput = false
    /// Engine status text while the model loads; cleared at the first `input`.
    public private(set) var loadingText: String?
    /// The loaded model and context size; set on `.session`, cleared on `.closed`.
    public private(set) var session: EngineSessionInfo?

    /// Indices of user rows the engine has not yet started a turn for.
    public private(set) var pendingUserRows: Set<Int> = []
    /// Subset of pending rows the engine reported as queued.
    public private(set) var queuedUserRows: Set<Int> = []

    public var pendingUserCount: Int { pendingUserRows.count }

    public func isPending(rowAt index: Int) -> Bool { pendingUserRows.contains(index) }
    public func isQueued(rowAt index: Int) -> Bool { queuedUserRows.contains(index) }

    public init() {}

    public mutating func appendUser(_ text: String) {
        pendingUserRows.insert(rows.count)
        rows.append(.user(text))
        isAwaitingInput = false
    }

    /// The process is gone: nothing is busy, loading or pending any more.
    public mutating func end() {
        isBusy = false
        isGenerating = false
        isAwaitingInput = false
        loadingText = nil
        session = nil
        clearPending()
    }

    private mutating func clearPending() {
        pendingUserRows = []
        queuedUserRows = []
    }

    /// Marks every pending row as queued behind the running turn.
    private mutating func markPendingQueued() {
        queuedUserRows = pendingUserRows
    }

    public mutating func appendSystem(_ text: String) {
        rows.append(.system(text))
    }

    public mutating func appendReport(_ markdown: String) {
        rows.append(.report(markdown))
    }

    /// Replaces every row with `divider` and the resumed turns (a relaunch
    /// is truthful only if the screen shows what the engine kept).
    public mutating func rebuild(from resumed: EngineResumed, divider: String) {
        clearPending()
        rows = [.divider(divider)]
        for turn in resumed.turns {
            rows.append(.user(turn.prompt))
            if turn.stopped {
                rows.append(.system("Stopped."))
            } else if let answer = turn.answer, !answer.isEmpty {
                rows.append(.answer(EngineAnswer(
                    text: answer, contextUsed: nil, contextSize: nil, durationMs: nil)))
            }
        }
    }

    public mutating func apply(_ event: EngineEvent) {
        switch event {
        case .prompt:
            clearPending()
            isBusy = true
            isAwaitingInput = false
        case .generating(let b):
            isGenerating = b
        case .loading(let text):
            loadingText = text
        case .awaitingInput:
            clearPending()
            loadingText = nil
            isBusy = false
            isGenerating = false
            isAwaitingInput = true
        case .narration(let t):
            rows.append(.narration(t))
        case .thinking(let t):
            rows.append(.thinking(t))
        case .toolStart(let tool):
            rows.append(.tool(EngineToolCard(tool: tool)))
        case .toolEnd(let tool, let ok, let ms):
            fillLastCard(matching: tool, missing: { $0.ok == nil }) {
                $0.ok = ok
                $0.durationMs = ms
            }
        case .toolRejected(let r):
            rows.append(.tool(EngineToolCard(tool: EngineTool(op: r.name, path: r.path), rejection: r)))
        case .toolResult(let result):
            fillLastCard(matching: result.tool, missing: { $0.result == nil }) {
                $0.result = result
            }
        case .answer(let a):
            if a.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append(.error(a.reason.map { "No answer: \($0)" }
                    ?? "No answer — the model stopped without answering"))
            } else {
                absorbOrAppend(a)
            }
        case .interrupted:
            rows.append(.system("Stopped."))
        case .turnEnded(let outcome):
            let text = "Turn ended: \(outcome)"
            rows.append(outcome == "answered" ? .system(text) : .error(text))
        case .queued:
            markPendingQueued()
        case .steering(let applied):
            clearPending()
            rows.append(.system(applied ? "Queued message delivered" : "Queued message not confirmed"))
        case .notice(let t):
            rows.append(.system(t))
        case .mentions(let attached, let missing):
            // Not a refusal: the prompt still goes to the model.
            rows.append(.mentions(attached: attached, missing: missing))
        case .refused(let t), .error(let t):
            clearPending()
            rows.append(.error(t))
        case .relaunch:
            clearPending()
        case .resumed(let r):
            rebuild(from: r, divider: r.divider(after: nil))
        case .session(let info):
            session = info
        case .startup(_, let summary):
            if let summary = summary?.trimmedOrNil { rows.append(.system(summary)) }
        case .conversationState(let state):
            rows.append(.system(MetricsFormatting.conversationStateLine(state)))
        case .analysis(let lines):
            // Column-aligned text, not Markdown: fenced, so it keeps its spacing.
            rows.append(.report("```\n" + lines.joined(separator: "\n") + "\n```"))
        case .closed:
            end()
        case .ready, .pause, .memory, .prefixCache, .protocolError, .ignored:
            break
        }
    }

    /// The latest row that isn't a user prompt, if it's a narration, becomes
    /// the answer in place (a prompt sent mid-turn stays after it); equal
    /// texts collapse to the answer alone. Otherwise the answer is appended.
    private mutating func absorbOrAppend(_ a: EngineAnswer) {
        guard let i = rows.lastIndex(where: { if case .user = $0 { false } else { true } }),
              case .narration(let n) = rows[i] else {
            rows.append(.answer(a))
            return
        }
        let same = n.trimmingCharacters(in: .whitespacesAndNewlines) == a.text.trimmingCharacters(in: .whitespacesAndNewlines)
        rows[i] = .answer(a, reply: same ? nil : n)
    }

    private mutating func fillLastCard(
        matching tool: EngineTool,
        missing: (EngineToolCard) -> Bool,
        fill: (inout EngineToolCard) -> Void
    ) {
        for i in rows.indices.reversed() {
            guard case .tool(var card) = rows[i],
                  card.rejection == nil,
                  card.tool.op == tool.op, card.tool.path == tool.path,
                  missing(card) else { continue }
            fill(&card)
            rows[i] = .tool(card)
            return
        }
    }
}
