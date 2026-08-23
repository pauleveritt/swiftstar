import Foundation

/// One parameter of a tool call, reconstructed from the phase stream.
public struct ToolParam: Equatable, Sendable {
    public let name: String
    public var value: String
}

/// A tool card: one tool call's rendered state, rebuilt from the wire's
/// `tool`/`param_begin`/`param_value`/`param_end`/`output`/`finish` phases
/// (D4). Only the bash family ever carries `output` (json-events.md); `status`
/// is non-nil when the block did not close cleanly (interrupt, parse error,
/// hard failure).
public struct ToolCard: Equatable, Sendable {
    public let name: String
    public var params: [ToolParam]
    public var output: String?
    public var status: String?
}

/// One display row of the agent transcript.
public enum AgentTranscriptRow: Equatable, Sendable {
    case thinking(String)
    case content(String)
    case tool(ToolCard)
    case system(String)
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
            if case .content(let existing)? = rows.last {
                rows[rows.count - 1] = .content(existing + text)
            } else {
                rows.append(.content(text))
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
        case .hello, .status, .ready, .queued, .ignored, .refused:
            break
        }
    }

    /// Non-wire sibling: user prompts and engine status lines are not NDJSON
    /// events, so they enter through a separate mutator (like ChatTranscript).
    public mutating func appendSystem(_ message: String) {
        rows.append(.system(message))
    }

    private mutating func applyTool(_ te: AgentToolEvent) {
        switch te.phase {
        case .start:
            cardRows = [:]
        case .tool:
            let card = ToolCard(name: te.name ?? "", params: [], output: nil, status: nil)
            rows.append(.tool(card))
            cardRows[te.idx] = rows.count - 1
        case .paramBegin:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.params.append(ToolParam(name: te.paramName ?? "", value: ""))
            rows[row] = .tool(card)
        case .paramValue:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row],
                  !card.params.isEmpty else { return }
            card.params[card.params.count - 1].value += te.value ?? ""
            rows[row] = .tool(card)
        case .paramEnd:
            break  // the param is already tracked by param_begin/param_value
        case .output:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.output = (card.output ?? "") + (te.value ?? "")
            rows[row] = .tool(card)
        case .finish:
            // `finish` carries the last real call's idx; a zero-call block
            // (calls == 0, idx == 0) has no card and is a no-op here.
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.status = te.status
            rows[row] = .tool(card)
        }
    }
}
