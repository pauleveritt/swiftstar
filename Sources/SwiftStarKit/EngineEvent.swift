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
    /// The run's capture file, under the session's directory (SU.7a); a
    /// `.partial.json` mid-session, which AN.2 takes the directory from.
    public let capturePath: String?

    public init(prefillTokens: Int?, prefillMs: Double?, evalCount: Int, evalMs: Double?, capturePath: String? = nil) {
        self.prefillTokens = prefillTokens
        self.prefillMs = prefillMs
        self.evalCount = evalCount
        self.evalMs = evalMs
        self.capturePath = capturePath
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
    /// On a miss, the key parts that differ from the nearest recorded entry;
    /// `[]` when this key's own entry failed to load; nil when nothing could
    /// be compared (ds4-engine `prefix_cache.rs:75-86`, EN.2).
    public let changed: [String]?
    /// On a hit, the fill that made the entry, when it was recorded.
    public let entryFillMs: Double?

    public init(
        outcome: String, tokens: Int?, loadMs: Double?, fillMs: Double?,
        changed: [String]? = nil, entryFillMs: Double? = nil
    ) {
        self.outcome = outcome
        self.tokens = tokens
        self.loadMs = loadMs
        self.fillMs = fillMs
        self.changed = changed
        self.entryFillMs = entryFillMs
    }
}

/// One of the engine's start-up reports (EN.2), in the order it sends them:
/// the commit the model works on, the candidate worktree, its environment
/// sync, the project's instructions, and the index primer at the first pause.
public enum EngineStartupPart: Equatable, Sendable {
    case baseline(commit: String?, excludedCount: Int?)
    case candidateReady(createdMs: Double?, waitedMs: Double?)
    case envSync(outcome: String, durationMs: Double?)
    case projectInstructions(file: String?, tokens: Int?, cut: Bool)
    case indexPrimed(sinceStartMs: Double?)
}

/// The start-up reports of this process, folded (the Session card's rows).
public struct EngineStartupInfo: Equatable, Sendable {
    public var commit: String?
    public var excludedCount: Int?
    public var candidateCreatedMs: Double?
    public var candidateWaitedMs: Double?
    public var envSyncOutcome: String?
    public var envSyncMs: Double?
    public var instructionsFile: String?
    public var instructionsTokens: Int?
    public var instructionsCut: Bool?
    public var indexPrimedMs: Double?

    public init(
        commit: String? = nil, excludedCount: Int? = nil,
        candidateCreatedMs: Double? = nil, candidateWaitedMs: Double? = nil,
        envSyncOutcome: String? = nil, envSyncMs: Double? = nil,
        instructionsFile: String? = nil, instructionsTokens: Int? = nil, instructionsCut: Bool? = nil,
        indexPrimedMs: Double? = nil
    ) {
        self.commit = commit
        self.excludedCount = excludedCount
        self.candidateCreatedMs = candidateCreatedMs
        self.candidateWaitedMs = candidateWaitedMs
        self.envSyncOutcome = envSyncOutcome
        self.envSyncMs = envSyncMs
        self.instructionsFile = instructionsFile
        self.instructionsTokens = instructionsTokens
        self.instructionsCut = instructionsCut
        self.indexPrimedMs = indexPrimedMs
    }

    public mutating func fold(_ part: EngineStartupPart) {
        switch part {
        case .baseline(let commit, let excluded):
            self.commit = commit
            excludedCount = excluded
        case .candidateReady(let created, let waited):
            candidateCreatedMs = created
            candidateWaitedMs = waited
        case .envSync(let outcome, let ms):
            envSyncOutcome = outcome
            envSyncMs = ms
        case .projectInstructions(let file, let tokens, let cut):
            instructionsFile = file
            instructionsTokens = tokens
            instructionsCut = cut
        case .indexPrimed(let ms):
            indexPrimedMs = ms
        }
    }
}

/// A resumed conversation's saved state, loaded or not (`conversation_state`,
/// ds4-engine `driver.rs:469-500`): sent once, on resume.
public struct EngineConversationState: Equatable, Sendable {
    /// `loaded`, `unsupported`, `failed` or `absent`.
    public let outcome: String
    public let bytes: Int64?
    public let loadMs: Double?
    public let error: String?

    public init(outcome: String, bytes: Int64?, loadMs: Double?, error: String?) {
        self.outcome = outcome
        self.bytes = bytes
        self.loadMs = loadMs
        self.error = error
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
    /// A start-up report; a non-empty `summary` is the line the engine means
    /// to show (its TUI shows it, `tui.py:250`).
    case startup(EngineStartupPart, summary: String?)
    case conversationState(EngineConversationState)
    /// A typed `/analyze`'s answer: the engine's report as text lines.
    case analysis([String])
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
    /// The files a prompt's `@` mentions attached, and the ones it couldn't
    /// ("name: reason"), SU.14.
    case mentions(attached: [String], missing: [String])
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
