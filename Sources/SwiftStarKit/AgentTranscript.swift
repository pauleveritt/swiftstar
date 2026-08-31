import Foundation

/// One parameter of a tool call, reconstructed from the phase stream.
/// `kind` is the wire's `param_kind` vocabulary (`path`, `offset`, `content`,
/// `diff_old`, `diff_new`, `bash_command`, `normal` — or "" when the event
/// carried none, e.g. P9 tool requests), so the view can render by kind
/// (content → syntax-highlighted, diff → tinted, path → header) instead of
/// scraping text.
public struct ToolParam: Equatable, Sendable {
    public let name: String
    public var value: String
    public let kind: String

    public init(name: String, value: String, kind: String = "") {
        self.name = name
        self.value = value
        self.kind = kind
    }
}

/// A tool card: one tool call's rendered state, rebuilt from the wire's
/// `tool`/`param_begin`/`param_value`/`param_end`/`output`/`finish` phases
/// (D4). Only the bash family ever carries `output` (json-events.md); `status`
/// is non-nil when the block did not close cleanly (interrupt, parse error,
/// hard failure). `path` is the value of the `path`-kinded param, surfaced in
/// the card header (and Quick Look-able). `finished` is set by the block's
/// `finish` phase — the view gates syntax highlighting on it, so an in-flight
/// card renders plain and a finished one re-typesets once.
public struct ToolCard: Equatable, Sendable {
    public let name: String
    public var params: [ToolParam]
    public var output: String?
    public var status: String?
    public var path: String? = nil
    public var finished: Bool = false
    public var startedAt: UInt64? = nil
    public var finishedAt: UInt64? = nil

    public var durationSeconds: Double? {
        guard let startedAt, let finishedAt, finishedAt >= startedAt else { return nil }
        return Double(finishedAt - startedAt) / 1_000_000
    }

    public var inputBytes: Int {
        params.reduce(0) { $0 + $1.value.utf8.count }
    }

    public var outputBytes: Int { output?.utf8.count ?? 0 }
}

/// Facts recorded when the app echoes a prompt. Token counts are deliberately
/// absent: the app does not own the engine tokenizer.
public struct UserRowStats: Equatable, Sendable {
    public let timestamp: Date
    public let characterCount: Int

    public init(timestamp: Date = Date(), characterCount: Int) {
        self.timestamp = timestamp
        self.characterCount = characterCount
    }

    public static func forText(_ text: String, at timestamp: Date = Date()) -> Self {
        Self(timestamp: timestamp, characterCount: text.count)
    }
}

/// Local provenance for an app-generated system row.
public struct SystemRowStats: Equatable, Sendable {
    public let timestamp: Date

    public init(timestamp: Date = Date()) { self.timestamp = timestamp }
}

/// Facts from a completed worker turn. The worker uses the same engine model
/// as the pool, so only facts actually present in its outcome are included.
public struct ConsultedRowStats: Equatable, Sendable {
    public let generatedTokens: Int?
    public let decodeTPS: Double?
    public let ctxUsed: Int?

    public init(generatedTokens: Int? = nil, decodeTPS: Double? = nil, ctxUsed: Int? = nil) {
        self.generatedTokens = generatedTokens
        self.decodeTPS = decodeTPS
        self.ctxUsed = ctxUsed
    }

    public var line: String? {
        var parts: [String] = []
        if let decodeTPS, decodeTPS.isFinite, decodeTPS > 0 {
            parts.append("Decode \(Int(decodeTPS.rounded())) tok/s")
        }
        if let generatedTokens { parts.append("\(generatedTokens) tok") }
        if let ctxUsed, ctxUsed > 0 { parts.append("ctx \(ctxUsed.formatted())") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A trace-backed context rebuild. `newTokens` is the compacted prefix and
/// `tailTokens` is the preserved tail appended after it.
public struct CompactionSummary: Equatable, Sendable {
    public let reason: String
    public let oldTokens: Int
    public let newTokens: Int
    public let tailStart: Int
    public let tailTokens: Int
    /// When the app observed the trace line. The trace's own wall timestamp is
    /// not needed for the facts and is intentionally not reconstructed here.
    public let observedAt: Date?

    public init(reason: String, oldTokens: Int, newTokens: Int, tailStart: Int,
                tailTokens: Int, observedAt: Date? = nil) {
        self.reason = reason
        self.oldTokens = oldTokens
        self.newTokens = newTokens
        self.tailStart = tailStart
        self.tailTokens = tailTokens
        self.observedAt = observedAt
    }

    public var retainedTokens: Int { newTokens + tailTokens }
    public var discardedTokens: Int { max(oldTokens - retainedTokens, 0) }

    public var line: String {
        var parts = ["ctx \(oldTokens.formatted()) → \(newTokens.formatted()) + \(tailTokens.formatted()) tail = \(retainedTokens.formatted()) tok"]
        if discardedTokens > 0 { parts.append("−\(discardedTokens.formatted())") }
        return parts.joined(separator: " · ")
    }
}

/// One display row of the agent transcript.
public enum AgentTranscriptRow: Equatable, Sendable {
    case user(String, stats: UserRowStats? = nil)
    case thinking(String)
    /// The assistant's prose, with the turn's frozen summary once it completes
    /// (the renderer shows it as a small static line under the bubble).
    case content(String, summary: TurnSummary?)
    case tool(ToolCard)
    /// A worker's final answer surfaced by `/chat` — a delegated artifact,
    /// rendered as its own panel (clearly not the main agent speaking).
    /// Carries the worker's id for the panel's provenance badge.
    case consulted(WorkerId, String, stats: ConsultedRowStats? = nil)
    case system(String, stats: SystemRowStats? = nil)
    case compaction(CompactionSummary)
}

/// Reduces `AgentEvent`s to display rows. Consecutive `.content` and
/// `.thinking` deltas coalesce into one row each (like `ChatTranscript`);
/// tool phases mutate the currently-open card in place, keyed by `idx` within
/// the current block (D4, json-events.md "The idx contract"). The card key map
/// is cleared at each block `start`, so a late `output` can never be
/// attributed to a same-`idx` call in the following block. The leading-newline
/// quirk (json-events.md "Known quirks": the first `text` after a `think`
/// starts with leading newlines) is stripped here, exactly once.
public struct AgentTranscript: Equatable, Sendable {
    public private(set) var rows: [AgentTranscriptRow] = []
    /// Card row index per `idx`, scoped to the current tool block.
    private var cardRows: [Int: Int] = [:]
    /// True while the last content event was `think`, so the next `text`
    /// strips leading whitespace exactly once.
    private var sawThink = false

    public init() {}

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .text(let s):
            var text = s
            if sawThink {
                text = String(text.drop(while: { $0.isWhitespace }))
                sawThink = false
            }
            if case .content(let existing, let summary)? = rows.last {
                rows[rows.count - 1] = .content(existing + text, summary: summary)
            } else {
                rows.append(.content(text, summary: nil))
            }
        case .think(let s):
            sawThink = true
            if case .thinking(let existing)? = rows.last {
                rows[rows.count - 1] = .thinking(existing + s)
            } else {
                rows.append(.thinking(s))
            }
        case .tool(let te):
            applyTool(te)
        case .toolRequest, .toolRequestRefused:
            break  // P9: the bidirectional request is not a transcript row (the host answers it); a malformed request is likewise not a row
        case .hello, .status, .ready, .queued, .ignored, .refused:
            break
        }
    }

    /// Non-wire sibling: user prompts and engine status lines are not NDJSON
    /// events, so they enter through a separate mutator (like ChatTranscript).
    public mutating func appendSystem(_ message: String) {
        rows.append(.system(message, stats: SystemRowStats()))
    }

    /// The user's own prompt echo — a real row (rendered as an accent pill),
    /// not a `> `-prefixed system line.
    public mutating func appendUser(_ message: String) {
        rows.append(.user(message, stats: UserRowStats.forText(message)))
    }

    /// Append a non-wire row directly (the generic entry point under the
    /// semantic mutators). The orchestrated-answer row uses it — the controller
    /// builds the row, the transcript only appends.
    public mutating func append(_ row: AgentTranscriptRow) {
        rows.append(row)
    }

    /// Freeze the turn's summary onto its reply bubble: attaches to the
    /// trailing `.content` row only. A turn that ends with a tool card (no
    /// prose) must not tag an earlier turn's content — so no trailing content
    /// row means no attachment.
    public mutating func attachSummary(_ summary: TurnSummary) {
        guard case .content(let text, _)? = rows.last else { return }
        rows[rows.count - 1] = .content(text, summary: summary)
    }

    private mutating func applyTool(_ te: AgentToolEvent) {
        switch te.phase {
        case .start:
            cardRows = [:]
        case .tool:
            let card = ToolCard(name: te.name ?? "", params: [], output: nil, status: nil,
                                startedAt: te.ts)
            rows.append(.tool(card))
            cardRows[te.idx] = rows.count - 1
        case .paramBegin:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.params.append(ToolParam(name: te.paramName ?? "", value: "", kind: te.paramKind ?? ""))
            rows[row] = .tool(card)
        case .paramValue:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row],
                  !card.params.isEmpty else { return }
            card.params[card.params.count - 1].value += te.value ?? ""
            rows[row] = .tool(card)
        case .paramEnd:
            // The just-ended param: a `path`-kinded one names the card's file
            // (its header and Quick Look target), so surface it on the card.
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row],
                  let ended = card.params.last else { return }
            if ended.kind == "path" { card.path = ended.value }
            rows[row] = .tool(card)
        case .output:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.output = (card.output ?? "") + (te.value ?? "")
            rows[row] = .tool(card)
        case .finish:
            // `finish` carries the last real call's idx; a zero-call block
            // (calls == 0, idx == 0) has no card and is a no-op here.
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.status = te.status
            card.finished = true
            card.finishedAt = te.ts
            rows[row] = .tool(card)
        }
    }
}
