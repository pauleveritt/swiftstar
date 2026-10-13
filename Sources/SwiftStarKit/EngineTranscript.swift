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
    /// declined call the engine stopped before its name.
    public var headerText: String {
        let op = tool.op.isEmpty && rejection != nil ? "a call" : tool.op
        if let path = tool.path, !path.isEmpty {
            return "\(op) \(path)"
        }
        return op
    }

    /// State and duration: `running`, or `succeeded`/`failed` with the time;
    /// `declined` with the reason for a call the engine refused.
    public var metadataLine: String {
        if let rejection { return "declined · \(rejection.label)" }
        var parts: [String] = []
        switch ok {
        case nil: parts.append("running")
        case true?: parts.append("succeeded")
        case false?: parts.append("failed")
        }
        if let ms = durationMs, ms.isFinite, ms >= 0 {
            parts.append(MetricsFormatting.duration(seconds: ms / 1000))
        }
        return parts.joined(separator: " · ")
    }

    /// The file the card names, for Quick Look: an absolute path as is, a
    /// relative one under `source` (the git root the engine works from).
    /// Nil without a path or a source.
    public func fileURL(source: URL?) -> URL? {
        guard let source, let path = tool.path, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        // `appending(path:)`, not `relativeTo:`, which drops the base's last
        // component when it has no trailing slash.
        return source.appending(path: path)
    }

    /// SF Symbol name for the tool's op.
    public var icon: String {
        if rejection != nil { return "xmark.circle" }
        switch tool.op {
        case "bash", "bash_status", "bash_stop": return "terminal"
        case "write": return "doc.badge.plus"
        case "edit": return "square.and.pencil"
        case "ls": return "folder"
        case "read", "more": return "doc.text.magnifyingglass"
        case "grep": return "magnifyingglass"
        default: return "wrench.and.screwdriver"
        }
    }
}

public enum TranscriptRow: Equatable, Sendable {
    case user(String)
    case narration(String)
    case thinking(String)
    case tool(EngineToolCard)
    case answer(EngineAnswer)
    case system(String)
    case error(String)
    /// Marks where a relaunch rebuilt the transcript.
    case divider(String)
}

/// Pure fold of `EngineEvent`s into transcript rows and busy flags.
///
/// Invariant: `rows` is append-only (rows are never removed or reordered),
/// which the index-based `pendingUserRows`/`queuedUserRows` rely on — except
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

    public var canStop: Bool { isBusy }
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
                rows.append(.answer(a))
            }
        case .interrupted:
            rows.append(.system("Stopped."))
        case .turnEnded(let outcome):
            let text = "Turn ended: \(outcome)"
            rows.append(outcome == "answered" ? .system(text) : .error(text))
        case .queued:
            markPendingQueued()
        case .steering(let applied, _):
            clearPending()
            rows.append(.system(applied ? "Queued message delivered" : "Queued message not confirmed"))
        case .notice(let t):
            rows.append(.system(t))
        case .refused(let t), .error(let t):
            clearPending()
            rows.append(.error(t))
        case .relaunch:
            clearPending()
        case .resumed(let r):
            rebuild(from: r, divider: r.divider(after: nil))
        case .session(let info):
            session = info
        case .closed:
            clearPending()
            session = nil
            loadingText = nil
            isBusy = false
            isGenerating = false
            isAwaitingInput = false
        case .ready, .pause, .memory, .protocolError, .ignored:
            break
        }
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
