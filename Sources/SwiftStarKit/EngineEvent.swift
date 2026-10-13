import Foundation

public struct EngineTool: Equatable, Sendable {
    public let op: String
    public let path: String?

    public init(op: String, path: String?) {
        self.op = op
        self.path = path
    }
}

public struct EngineToolResult: Equatable, Sendable {
    public let tool: EngineTool
    public let preview: String
    public let truncated: Bool

    public init(tool: EngineTool, preview: String, truncated: Bool) {
        self.tool = tool
        self.preview = preview
        self.truncated = truncated
    }
}

/// A call the engine refused before running it (`tool_rejected`, TUI.36):
/// the model is told and goes on, or (`not-approved`) the run ends.
public struct EngineToolRejection: Equatable, Sendable {
    public let name: String
    public let reason: String
    public let path: String?
    public let text: String

    public init(name: String, reason: String, path: String?, text: String) {
        self.name = name
        self.reason = reason
        self.path = path
        self.text = text
    }

    /// `reason` in a few words for the card; an unknown reason is shown as sent.
    public var label: String {
        switch reason {
        case "repeated-call": "repeated"
        case "call-cycle": "loop"
        case "unknown-tool": "unknown tool"
        case "path-refused": "path refused"
        default: reason
        }
    }
}

/// A `/resume`, `/model` or `/rewind` the engine won't do in place under
/// `--ndjson` (TUI.34): the front-end quits, then starts the executable with
/// `argv` exactly as given.
public struct EngineRelaunch: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case resume, model, rewind }
    public let kind: Kind
    public let argv: [String]
    public let reason: String

    public init(kind: Kind, argv: [String], reason: String) {
        self.kind = kind
        self.argv = argv
        self.reason = reason
    }

    /// The value after `--model-id` in `argv`, if any (`/model` sets one).
    public var modelID: String? {
        guard let i = argv.firstIndex(of: "--model-id"), i + 1 < argv.count else { return nil }
        return argv[i + 1]
    }
}

/// What a relaunched (resumed) process reports before its first `input`:
/// the turns the conversation holds, up to a rewind's snapshot.
public struct EngineResumed: Equatable, Sendable {
    public struct Turn: Equatable, Sendable {
        public let prompt: String
        public let answer: String?
        public let stopped: Bool

        public init(prompt: String, answer: String?, stopped: Bool) {
            self.prompt = prompt
            self.answer = answer
            self.stopped = stopped
        }
    }

    public let sessionID: String
    public let turns: [Turn]
    public let rewoundTo: Int?
    public let filesChanged: Int?
    public let contextUsed: Int?

    public init(sessionID: String, turns: [Turn], rewoundTo: Int?, filesChanged: Int?, contextUsed: Int?) {
        self.sessionID = sessionID
        self.turns = turns
        self.rewoundTo = rewoundTo
        self.filesChanged = filesChanged
        self.contextUsed = contextUsed
    }

    /// The divider above the rebuilt transcript, by what caused the relaunch.
    public func divider(after relaunch: EngineRelaunch?) -> String {
        switch relaunch?.kind {
        case .rewind?:
            return "Rewound to prompt \(rewoundTo.map(String.init) ?? "?")"
        case .model?:
            return "Switched to \(relaunch?.modelID ?? "another model"): new conversation, files kept"
        case .resume?, nil:
            return "Resumed session \(sessionID)"
        }
    }
}

public struct EngineAnswer: Equatable, Sendable {
    public let text: String
    public let contextUsed: Int?
    public let contextSize: Int?
    public let durationMs: Double?
    /// Why the engine gave no text (`tools-closed`, `no-final-text`, …).
    public let reason: String?

    public init(text: String, contextUsed: Int?, contextSize: Int?, durationMs: Double?, reason: String? = nil) {
        self.reason = reason
        self.text = text
        self.contextUsed = contextUsed
        self.contextSize = contextSize
        self.durationMs = durationMs
    }

    /// The small telemetry line shown under an answer: duration and/or
    /// context usage, joined, or nil if neither is present.
    public var summary: String? { summary(locale: .current) }

    public func summary(locale: Locale) -> String? {
        var parts: [String] = []
        if let ms = durationMs, ms.isFinite, ms >= 0 {
            parts.append(MetricsFormatting.duration(seconds: ms / 1000))
        }
        if let contextUsed, let contextSize {
            parts.append("ctx \(MetricsFormatting.number(contextUsed, locale: locale)) / "
                + MetricsFormatting.number(contextSize, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Per-pause measurements from a `checkpoint` snapshot; every field but
/// `evalCount` may be absent (the engine's snapshots are partial).
public struct PauseMetrics: Equatable, Sendable {
    public let prefillTokens: Int?
    public let prefillMs: Double?
    public let evalCount: Int
    public let evalMs: Double?

    public init(prefillTokens: Int?, prefillMs: Double?, evalCount: Int, evalMs: Double?) {
        self.prefillTokens = prefillTokens
        self.prefillMs = prefillMs
        self.evalCount = evalCount
        self.evalMs = evalMs
    }
}

public struct EngineMemory: Equatable, Sendable {
    public let allocatedBytes: Int64?
    public let budgetBytes: Int64?
    public let planGiB: Double?

    public init(allocatedBytes: Int64?, budgetBytes: Int64?, planGiB: Double?) {
        self.allocatedBytes = allocatedBytes
        self.budgetBytes = budgetBytes
        self.planGiB = planGiB
    }
}

public struct EngineSessionInfo: Equatable, Sendable {
    public let modelID: String?
    public let contextSize: Int?
    /// The engine's DFlash decision (`session.dflash`); nil when it sends none.
    public let dflash: EngineDFlash?

    public init(modelID: String?, contextSize: Int?, dflash: EngineDFlash? = nil) {
        self.modelID = modelID
        self.contextSize = contextSize
        self.dflash = dflash
    }
}

/// DFlash on or off for this run, and why, in the engine's words
/// (ds4-engine `dflash.py`, `Choice.event`).
public struct EngineDFlash: Equatable, Sendable {
    public let on: Bool
    public let reason: String
    /// The drafter model's path, when DFlash is on.
    public let drafter: String?

    public init(on: Bool, reason: String, drafter: String?) {
        self.on = on
        self.reason = reason
        self.drafter = drafter
    }
}

/// The prompt-prefix cache's outcome, sent whenever the engine fills the
/// system prefix: the first prompt, and again after `/clear` or a compaction.
/// A resumed conversation sends none. A hit's tokens are loaded, not
/// prefilled.
public struct EnginePrefixCache: Equatable, Sendable {
    /// "hit", "miss", or another word from the engine.
    public let outcome: String
    public let tokens: Int?
    public let loadMs: Double?
    public let fillMs: Double?

    public init(outcome: String, tokens: Int?, loadMs: Double?, fillMs: Double?) {
        self.outcome = outcome
        self.tokens = tokens
        self.loadMs = loadMs
        self.fillMs = fillMs
    }
}

public enum EngineEvent: Equatable, Sendable {
    case ready
    case loading(String)
    case session(EngineSessionInfo)
    case generating(Bool)
    case prompt(String)
    case narration(String)
    case thinking(String)
    case toolStart(EngineTool)
    case toolEnd(EngineTool, ok: Bool, durationMs: Double?)
    case toolResult(EngineToolResult)
    case toolRejected(EngineToolRejection)
    case answer(EngineAnswer)
    case pause(PauseMetrics)
    case memory(EngineMemory)
    case prefixCache(EnginePrefixCache)
    /// Stop took effect; carries the context after the interrupt.
    case interrupted(contextUsed: Int?, contextSize: Int?)
    /// The engine ended the session's turn (`terminal`): followed by `close`.
    case turnEnded(outcome: String)
    /// A prompt was queued behind the running turn (`count` now pending).
    case queued(count: Int)
    /// A queued message was (not) confirmed delivered after a tool resume.
    case steering(applied: Bool)
    case notice(String)
    case refused(String)
    /// A refusal that carries a `relaunch` argv the front-end acts on.
    case relaunch(EngineRelaunch)
    /// The relaunched process's conversation so far.
    case resumed(EngineResumed)
    case awaitingInput
    case error(String)
    case closed(capturePath: String?)
    case protocolError(String)
    case ignored
}
