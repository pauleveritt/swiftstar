import Foundation

public enum EngineSessionPhase: Equatable, Sendable {
    case idle
    case starting
    case running
    case quitting
    case ended(EngineExit)
    case notFound([String])

    /// Shown above the prompt when the engine could not be found.
    public var notFoundNotice: String? {
        guard case .notFound(let searched) = self else { return nil }
        return "ds4-dogfood was not found. Searched:\n" + searched.joined(separator: "\n")
    }

    /// A process exists or is being torn down; starting another is refused.
    public var isActive: Bool {
        switch self {
        case .starting, .running, .quitting: true
        case .idle, .ended, .notFound: false
        }
    }
}

/// The composer's one button.
public enum ComposerButton: Equatable, Sendable {
    case send(enabled: Bool)
    case stop
}

/// What the composer may do and the status text beside it.
public struct EngineComposer: Equatable, Sendable {
    /// Typing and sending go together: the field is enabled exactly when a
    /// prompt can be sent (the engine queues one sent while busy).
    public var canSend: Bool
    public var canStop: Bool
    public var label: String

    /// Busy with an empty field, the button stops; with text typed it sends,
    /// and the engine queues the prompt.
    public func button(forInput input: String) -> ComposerButton {
        let text = input.trimmedOrNil
        if canStop, text == nil { return .stop }
        return .send(enabled: canSend && text != nil)
    }

    public static func state(phase: EngineSessionPhase, transcript: EngineTranscript) -> EngineComposer {
        switch phase {
        case .idle:
            return EngineComposer(canSend: false, canStop: false, label: "Not started")
        case .starting:
            return EngineComposer(canSend: false, canStop: false, label: "Starting…")
        case .running:
            let busy = transcript.isBusy
            let label: String
            if transcript.loadingText != nil {
                let queued = transcript.pendingUserCount
                label = queued > 0 ? "Loading model… · \(queued) queued" : "Loading model…"
            } else {
                label = transcript.isGenerating ? "Generating…" : busy ? "Working…" : "Ready"
            }
            return EngineComposer(canSend: true, canStop: busy, label: label)
        case .quitting:
            return EngineComposer(canSend: false, canStop: false, label: "Ending…")
        case .ended(let exit):
            return EngineComposer(canSend: false, canStop: false, label: exit.message)
        case .notFound:
            return EngineComposer(canSend: false, canStop: false, label: "ds4-dogfood not found")
        }
    }
}

/// Owns phase, transcript and metrics and applies events, exit and quit, so
/// the rules are testable without a subprocess. `EngineController` forwards.
public struct EngineSessionModel: Equatable, Sendable {
    public private(set) var phase: EngineSessionPhase = .idle
    public private(set) var transcript = EngineTranscript()
    public private(set) var metrics = EngineMetricsState()
    /// The relaunch the controller is running (`didRelaunch`), used for the
    /// divider when `.resumed` arrives. Not set by a `.relaunch` event: when
    /// two refusals arrive, only the one actually run may name the divider.
    public private(set) var pendingRelaunch: EngineRelaunch?

    /// The session directory this conversation is known by (SU.7a): the one
    /// a `.resumed` names, else this process's own, from the first pause's
    /// capture path. Cleared by a fresh start.
    public private(set) var currentSessionID: String?

    public init() {}

    public var composer: EngineComposer {
        EngineComposer.state(phase: phase, transcript: transcript)
    }

    /// A new session begins: fresh transcript and metrics, phase `starting`.
    public mutating func didStart() {
        transcript = EngineTranscript()
        metrics = EngineMetricsState()
        pendingRelaunch = nil
        currentSessionID = nil
        phase = .starting
    }

    /// A relaunch begins: like `didStart()`, but the rows and the old
    /// session's pointer stay until `.resumed` replaces them, so a relaunch
    /// the engine refuses to start leaves the conversation on screen.
    public mutating func didRelaunch(_ relaunch: EngineRelaunch) {
        transcript.end()
        metrics = EngineMetricsState()
        pendingRelaunch = relaunch
        phase = .starting
    }

    /// A start has begun but nothing is spawned yet (the model list is still
    /// loading): the composer reads "Starting…"; the transcript is untouched.
    public mutating func willStart() {
        phase = .starting
    }

    public mutating func didNotFind(searched: [String]) {
        phase = .notFound(searched)
    }

    public mutating func apply(_ event: EngineEvent) {
        if case .ready = event, phase == .starting { phase = .running }
        if case .protocolError(let message) = event {
            transcript.appendSystem("Protocol error: \(message)")
        }
        switch event {
        case .resumed(let r):
            transcript.rebuild(from: r, divider: r.divider(after: pendingRelaunch))
            pendingRelaunch = nil
            if !r.sessionID.isEmpty { currentSessionID = r.sessionID }
        default:
            transcript.apply(event)
        }
        if case .pause(let p) = event, currentSessionID == nil,
           let path = p.capturePath, let id = EngineSessionEntry.directoryID(fromCapturePath: path) {
            currentSessionID = id
        }
        EngineMetricsReducer.reduce(&metrics, event)
    }

    public mutating func didExit(_ exit: EngineExit, directory: URL?) {
        transcript.end()
        transcript.appendSystem(exit.message)
        if let directory {
            transcript.appendSystem(
                "Session: \(directory.path)\nTo take its changes: \(EngineCommand.applyCommand(sessionDirectory: directory))")
        }
        phase = .ended(exit)
    }

    public mutating func willQuit() {
        if phase.isActive { phase = .quitting }
    }

    /// Records the prompt as a pending row; false means nothing may be sent.
    public mutating func send(_ text: String) -> Bool {
        guard phase == .running else { return false }
        transcript.appendUser(text)
        return true
    }
}
