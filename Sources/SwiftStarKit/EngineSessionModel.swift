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
    /// This session's directory, from the first checkpoint's capture path;
    /// a relaunch is a new session, so it starts unknown again.
    public private(set) var sessionDirectory: URL?
    /// An analysis in progress (AN.2), from Analyze until Done's return.
    public private(set) var analysis: EngineAnalysis?

    public init() {}

    /// Analyze is offered: idle at `input`, nothing pending, the directory
    /// known, and no analysis already under way.
    public var canAnalyze: Bool {
        phase == .running && !transcript.isBusy && transcript.isAwaitingInput
            && transcript.pendingUserCount == 0 && sessionDirectory != nil && analysis == nil
    }

    /// Starts an analysis of this session: returns the relaunch that resumes
    /// it as a fork, or nil when Analyze isn't offered.
    public mutating func beginAnalysis(report: String, source: URL) -> EngineRelaunch? {
        guard canAnalyze, let main = sessionDirectory else { return nil }
        analysis = EngineAnalysis(stage: .forking(main: main, report: report))
        transcript.appendSystem(EngineAnalysis.forkingNotice)
        return EngineRelaunch(
            kind: .resume,
            argv: EngineCommand.forkArguments(sessionDirectory: main, source: source),
            reason: "analysis")
    }

    /// The analysis prompt, once, when the fork is at `input`; it also adds
    /// the report card.
    public mutating func takeAnalysisPrompt() -> (text: String, shown: String)? {
        guard case .analyzing(let main, let firstRow, let report, false)? = analysis?.stage,
              phase == .running, transcript.isAwaitingInput, !transcript.isBusy
        else { return nil }
        transcript.appendReport(report)
        analysis = EngineAnalysis(stage: .analyzing(main: main, firstRow: firstRow, report: report, promptSent: true))
        return (EngineAnalysis.prompt(report: report), EngineAnalysis.promptShown)
    }

    /// Done's command, when the fork is idle: resume the main session.
    public var analysisDoneCommand: String? {
        guard case .analyzing(let main, _, _, _)? = analysis?.stage,
              phase == .running, !transcript.isBusy, transcript.isAwaitingInput,
              transcript.pendingUserCount == 0
        else { return nil }
        return "/resume \(main.lastPathComponent)"
    }

    public mutating func markAnalysisReturning() {
        guard case .analyzing(let main, let firstRow, let report, _)? = analysis?.stage,
              analysisDoneCommand != nil
        else { return }
        analysis = EngineAnalysis(stage: .returning(main: main, firstRow: firstRow, report: report))
    }

    /// The banner shows once the fork is up, until the return lands.
    public var showsAnalysisBanner: Bool {
        switch analysis?.stage {
        case .analyzing?, .returning?: true
        case .forking?, nil: false
        }
    }

    /// Done would act now.
    public var canFinishAnalysis: Bool { analysisDoneCommand != nil }

    public var composer: EngineComposer {
        EngineComposer.state(phase: phase, transcript: transcript)
    }

    /// A new session begins: fresh transcript and metrics, phase `starting`.
    public mutating func didStart() {
        transcript = EngineTranscript()
        metrics = EngineMetricsState()
        pendingRelaunch = nil
        sessionDirectory = nil
        analysis = nil
        phase = .starting
    }

    /// A relaunch begins: like `didStart()`, but the rows and the old
    /// session's pointer stay until `.resumed` replaces them, so a relaunch
    /// the engine refuses to start leaves the conversation on screen.
    public mutating func didRelaunch(_ relaunch: EngineRelaunch) {
        transcript.end()
        metrics = EngineMetricsState()
        pendingRelaunch = relaunch
        sessionDirectory = nil
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
            transcript.rebuild(from: r, divider: divider(for: r))
            pendingRelaunch = nil
        case .pause(let m):
            if sessionDirectory == nil, let path = m.capturePath {
                sessionDirectory = URL(fileURLWithPath: path).deletingLastPathComponent()
            }
            transcript.apply(event)
        case .refused:
            // Done's `/resume` refused without a relaunch: still in the fork.
            if case .returning(let main, let firstRow, let report)? = analysis?.stage {
                analysis = EngineAnalysis(stage: .analyzing(
                    main: main, firstRow: firstRow, report: report, promptSent: true))
            }
            transcript.apply(event)
        default:
            transcript.apply(event)
        }
        EngineMetricsReducer.reduce(&metrics, event)
    }

    /// A rebuild's divider, and the analysis's next stage: the fork's
    /// `resumed` starts it, the return's ends it, and any other ends it with
    /// that relaunch's own divider.
    private mutating func divider(for r: EngineResumed) -> String {
        switch analysis?.stage {
        case .forking(let main, let report)?:
            analysis = EngineAnalysis(stage: .analyzing(
                main: main, firstRow: 1 + rowCount(of: r), report: report, promptSent: false))
            return EngineAnalysis.forkDivider
        case .returning?:
            analysis = nil
            return EngineAnalysis.returnDivider(prompts: r.turns.count)
        default:
            analysis = nil
            return r.divider(after: pendingRelaunch)
        }
    }

    /// The rows `rebuild` makes for `r`'s turns, after its divider.
    private func rowCount(of r: EngineResumed) -> Int {
        var t = EngineTranscript()
        t.rebuild(from: r, divider: "")
        return t.rows.count - 1
    }

    public mutating func didExit(_ exit: EngineExit, directory: URL?) {
        // Forking and returning begin by quitting the running session; that
        // exit comes before the relaunch starts and is expected. An exit
        // after it (the new process failed) or while analyzing ends it.
        var failedFrom: URL?
        switch analysis?.stage {
        case .forking?, .returning?:
            if pendingRelaunch != nil {
                failedFrom = analysis?.main
                analysis = nil
            }
        default:
            analysis = nil
        }
        transcript.end()
        defer {
            if let failedFrom { transcript.appendSystem(EngineAnalysis.mainUnchanged(failedFrom)) }
        }
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
    /// `shown` is the bubble's text when it differs from what the engine gets.
    public mutating func send(_ text: String, shown: String? = nil) -> Bool {
        guard phase == .running else { return false }
        transcript.appendUser(shown ?? text)
        return true
    }
}
