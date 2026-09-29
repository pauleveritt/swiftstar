import Foundation

public enum EngineSessionPhase: Equatable, Sendable {
    case idle
    case starting
    case running
    case quitting
    case ended(EngineExit)
    case notFound([String])

    /// A process exists or is being torn down; starting another is refused.
    public var isActive: Bool {
        switch self {
        case .starting, .running, .quitting: true
        case .idle, .ended, .notFound: false
        }
    }
}

/// What the composer may do and the status text beside it.
public struct EngineComposer: Equatable, Sendable {
    public var canType: Bool
    public var canSend: Bool
    public var canStop: Bool
    public var label: String

    public static func state(phase: EngineSessionPhase, transcript: EngineTranscript) -> EngineComposer {
        switch phase {
        case .idle:
            return EngineComposer(canType: false, canSend: false, canStop: false, label: "Not started")
        case .starting:
            return EngineComposer(canType: false, canSend: false, canStop: false, label: "Starting…")
        case .running:
            let busy = transcript.isBusy
            let label: String
            if transcript.loadingText != nil {
                let queued = transcript.pendingUserCount
                label = queued > 0 ? "Loading model… · \(queued) queued" : "Loading model…"
            } else {
                label = transcript.isGenerating ? "Generating…" : busy ? "Working…" : "Ready"
            }
            return EngineComposer(canType: true, canSend: true, canStop: busy, label: label)
        case .quitting:
            return EngineComposer(canType: false, canSend: false, canStop: false, label: "Ending…")
        case .ended(let exit):
            return EngineComposer(canType: false, canSend: false, canStop: false, label: exit.message)
        case .notFound:
            return EngineComposer(canType: false, canSend: false, canStop: false, label: "ds4-dogfood not found")
        }
    }
}

/// Owns phase, transcript and metrics and applies events, exit and quit, so
/// the rules are testable without a subprocess. `EngineController` forwards.
public struct EngineSessionModel: Equatable, Sendable {
    public private(set) var phase: EngineSessionPhase = .idle
    public private(set) var transcript = EngineTranscript()
    public private(set) var metrics = EngineMetricsState()
    public private(set) var sessionDirectory: URL?

    public init() {}

    public var composer: EngineComposer {
        EngineComposer.state(phase: phase, transcript: transcript)
    }

    /// A new session begins: fresh transcript and metrics, phase `starting`.
    public mutating func didStart() {
        transcript = EngineTranscript()
        metrics = EngineMetricsState()
        sessionDirectory = nil
        phase = .starting
    }

    public mutating func didNotFind(searched: [String]) {
        phase = .notFound(searched)
    }

    /// The process could not be launched at all.
    public mutating func didFailToLaunch(_ exit: EngineExit) {
        transcript.end()
        transcript.appendSystem(exit.message)
        phase = .ended(exit)
    }

    public mutating func apply(_ event: EngineEvent) {
        if case .ready = event, phase == .starting { phase = .running }
        if case .protocolError(let message) = event {
            transcript.appendSystem("Protocol error: \(message)")
        }
        transcript.apply(event)
        EngineMetricsReducer.reduce(&metrics, event)
    }

    public mutating func didExit(_ exit: EngineExit, directory: URL?) {
        sessionDirectory = directory
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
