import Foundation

public struct EngineToolCard: Equatable, Sendable {
    public var tool: EngineTool
    public var ok: Bool?
    public var durationMs: Double?
    public var result: EngineToolResult?

    public init(tool: EngineTool, ok: Bool? = nil, durationMs: Double? = nil, result: EngineToolResult? = nil) {
        self.tool = tool
        self.ok = ok
        self.durationMs = durationMs
        self.result = result
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
}

/// Pure fold of `EngineEvent`s into transcript rows and busy flags.
public struct EngineTranscript: Equatable, Sendable {
    public private(set) var rows: [TranscriptRow] = []
    public private(set) var isBusy = false
    public private(set) var isGenerating = false
    public private(set) var isAwaitingInput = false
    /// Engine status text while the model loads; cleared at the first `input`.
    public private(set) var loadingText: String?
    /// The loaded model and context size; set on `.session`, cleared on `.closed`.
    public private(set) var session: EngineSessionInfo?

    public var canStop: Bool { isBusy }

    public init() {}

    public mutating func appendUser(_ text: String) {
        rows.append(.user(text))
        isBusy = true
        isAwaitingInput = false
    }

    public mutating func appendSystem(_ text: String) {
        rows.append(.system(text))
    }

    public mutating func apply(_ event: EngineEvent) {
        switch event {
        case .prompt:
            isBusy = true
            isAwaitingInput = false
        case .generating(let b):
            isGenerating = b
        case .loading(let text):
            loadingText = text
        case .awaitingInput:
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
        case .toolResult(let result):
            fillLastCard(matching: result.tool, missing: { $0.result == nil }) {
                $0.result = result
            }
        case .answer(let a):
            rows.append(.answer(a))
        case .interrupted:
            rows.append(.system("Stopped."))
        case .notice(let t):
            rows.append(.system(t))
        case .refused(let t), .error(let t):
            rows.append(.error(t))
        case .session(let info):
            session = info
        case .closed:
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
                  card.tool.op == tool.op, card.tool.path == tool.path,
                  missing(card) else { continue }
            fill(&card)
            rows[i] = .tool(card)
            return
        }
    }
}
