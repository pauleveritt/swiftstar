import Testing
import Foundation
@testable import SwiftStarKit

struct EngineSessionModelTests {
    private func running() -> EngineSessionModel {
        var m = EngineSessionModel()
        m.didStart()
        m.apply(.ready)
        return m
    }

    private func resumedEvent() -> EngineEvent {
        .resumed(EngineResumed(sessionID: "s", turns: [], rewoundTo: 1, filesChanged: nil, contextUsed: nil))
    }

    // MARK: steps → phase and composer

    /// One thing done to a session model, so a table row can script a run.
    enum Step: Sendable {
        case willStart, didStart, ready, loading, awaitingInput, generating, willQuit, exit, notFound
        case prompt(String), send(String)
    }

    private static func play(_ steps: [Step]) -> EngineSessionModel {
        var m = EngineSessionModel()
        for step in steps {
            switch step {
            case .willStart: m.willStart()
            case .didStart: m.didStart()
            case .ready: m.apply(.ready)
            case .loading: m.apply(.loading("mapping weights"))
            case .awaitingInput: m.apply(.awaitingInput)
            case .generating: m.apply(.generating(true))
            case .willQuit: m.willQuit()
            case .exit: m.didExit(EngineExit(code: 0, message: "ended"), directory: nil)
            case .notFound: m.didNotFind(searched: ["/x"])
            case .prompt(let text): m.apply(.prompt(text))
            case .send(let text): _ = m.send(text)
            }
        }
        return m
    }

    struct LabelCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let steps: [Step]
        let label: String
        var phase: EngineSessionPhase? = nil
        var canSend: Bool? = nil
        var canStop: Bool? = nil
    }

    private static let loaded: [Step] = [.didStart, .ready, .loading]

    static let labelCases: [LabelCase] = [
        .init(testDescription: "composerLabels (not started)", steps: [], label: "Not started", phase: .idle),
        .init(testDescription: "willStartShowsStarting", steps: [.willStart], label: "Starting…", phase: .starting),
        .init(testDescription: "composerLabels (didStart)", steps: [.didStart], label: "Starting…", phase: .starting),
        .init(testDescription: "readyMovesToRunning", steps: [.didStart, .ready], label: "Ready", phase: .running),
        .init(testDescription: "composerLabels (loading)", steps: loaded, label: "Loading model…"),
        .init(testDescription: "composerLabels (queued)", steps: loaded + [.send("a"), .send("b")],
              label: "Loading model… · 2 queued"),
        .init(testDescription: "composerLabels (ready)", steps: loaded + [.awaitingInput], label: "Ready",
              canSend: true, canStop: false),
        .init(testDescription: "generatingLabelComesFromComposer (working)", steps: [.didStart, .ready, .prompt("hi")],
              label: "Working…", canSend: true, canStop: true),
        .init(testDescription: "generatingLabelComesFromComposer",
              steps: [.didStart, .ready, .prompt("hi"), .generating], label: "Generating…"),
        .init(testDescription: "willQuitMovesToQuitting", steps: [.didStart, .ready, .prompt("a"), .willQuit],
              label: "Ending…", phase: .quitting, canSend: false),
        .init(testDescription: "composerLabels (ended)", steps: [.didStart, .ready, .willQuit, .exit], label: "ended",
              phase: .ended(EngineExit(code: 0, message: "ended"))),
        .init(testDescription: "composerLabels (not found)", steps: [.notFound], label: "ds4-dogfood not found",
              phase: .notFound(["/x"])),
    ]

    @Test(arguments: labelCases) func phaseAndLabel(_ c: LabelCase) {
        let m = Self.play(c.steps)
        #expect(m.composer.label == c.label)
        if let phase = c.phase { #expect(m.phase == phase) }
        if let canSend = c.canSend { #expect(m.composer.canSend == canSend) }
        if let canStop = c.canStop { #expect(m.composer.canStop == canStop) }
    }

    @Test(arguments: [
        (EngineSessionPhase.quitting, true), (.starting, true), (.running, true), (.idle, false),
        (.ended(EngineExit(code: 0, message: "ended")), false), (.notFound([]), false),
    ]) func quittingIsActive(_ phase: EngineSessionPhase, _ active: Bool) {
        #expect(phase.isActive == active)
    }

    struct SendCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let steps: [Step]
        let sent: Bool
        let pending: Int
    }

    static let sendCases: [SendCase] = [
        .init(testDescription: "sendAcceptedWhileRunning", steps: [.didStart, .ready], sent: true, pending: 1),
        .init(testDescription: "canSendWhileBusy (mid-turn prompt shows as queued)",
              steps: [.didStart, .ready, .prompt("x")], sent: true, pending: 1),
        .init(testDescription: "sendRefusedWhileQuitting", steps: [.didStart, .ready, .willQuit], sent: false,
              pending: 0),
    ]

    @Test(arguments: sendCases) func send(_ c: SendCase) {
        var m = Self.play(c.steps)
        let before = m.transcript.rows
        #expect(m.send("hi") == c.sent)
        #expect(m.transcript.rows == (c.sent ? before + [.user("hi")] : before))
        #expect(m.transcript.pendingUserCount == c.pending)
    }

    struct ButtonCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let steps: [Step]
        let input: String
        let button: ComposerButton
    }

    private static let idle: [Step] = [.didStart, .ready, .awaitingInput]
    private static let busy: [Step] = idle + [.send("go"), .prompt("go")]

    static let buttonCases: [ButtonCase] = [
        .init(testDescription: "composerButtonStates (idle, text)", steps: idle, input: "hi",
              button: .send(enabled: true)),
        .init(testDescription: "composerButtonStates (idle, blank)", steps: idle, input: "  ",
              button: .send(enabled: false)),
        .init(testDescription: "composerButtonStates (busy, empty)", steps: busy, input: "", button: .stop),
        .init(testDescription: "composerButtonStates (busy, text)", steps: busy, input: "more",
              button: .send(enabled: true)),
        .init(testDescription: "composerButtonStates (not started)", steps: [], input: "hi",
              button: .send(enabled: false)),
    ]

    @Test(arguments: buttonCases) func composerButtonStates(_ c: ButtonCase) {
        #expect(Self.play(c.steps).composer.button(forInput: c.input) == c.button)
    }

    // MARK: SU.7a: the current session's directory id

    @Test func currentSessionIDFromResumed() {
        var m = running()
        m.apply(.resumed(EngineResumed(sessionID: "a", turns: [], rewoundTo: nil, filesChanged: nil, contextUsed: nil)))
        #expect(m.currentSessionID == "a")
        // A later pause names this process's own directory; the chain's id stays.
        m.apply(.pause(PauseMetrics(prefillTokens: 1, prefillMs: 1, evalCount: 1, evalMs: 1,
                                    capturePath: "/s/sessions/c/run-1.partial.json")))
        #expect(m.currentSessionID == "a")
    }

    @Test func currentSessionIDFromFirstPause() {
        var m = running()
        m.apply(.pause(PauseMetrics(prefillTokens: 1, prefillMs: 1, evalCount: 1, evalMs: 1,
                                    capturePath: "/s/sessions/b/run-1.partial.json")))
        #expect(m.currentSessionID == "b")
        m.didStart()
        #expect(m.currentSessionID == nil)
    }

    // MARK: relaunch

    /// Final review, Important #1: the divider names the relaunch that ran,
    /// not the last refusal that arrived.
    @Test func dividerNamesTheExecutedRelaunch() {
        var m = running()
        m.apply(.relaunch(EngineRelaunch(kind: .rewind, argv: ["tui", "--ndjson"], reason: "")))
        m.apply(.relaunch(EngineRelaunch(kind: .model, argv: ["--model-id", "x", "--ndjson"], reason: "")))
        m.didRelaunch(EngineRelaunch(kind: .rewind, argv: ["tui", "--ndjson"], reason: ""))
        m.apply(.ready)
        m.apply(resumedEvent())
        #expect(m.transcript.rows.first == .divider("Rewound to prompt 1"))
        #expect(m.pendingRelaunch == nil)
    }

    @Test func freshStartForgetsARelaunch() {
        var m = running()
        m.didRelaunch(EngineRelaunch(kind: .rewind, argv: ["tui", "--ndjson"], reason: ""))
        m.didStart()
        m.apply(.ready)
        m.apply(resumedEvent())
        #expect(m.transcript.rows.first == .divider("Resumed session s"))
    }

    /// Final review, Important #2: until the relaunched process has proved it
    /// starts, the old rows (and the session pointer) stay.
    @Test func didRelaunchKeepsRows() {
        var m = running()
        _ = m.send("hi")
        m.apply(.prompt("hi"))
        m.apply(.answer(EngineAnswer(text: "hello", contextUsed: nil, contextSize: nil, durationMs: nil)))
        m.didExit(EngineExit(code: 0, message: "ended"), directory: URL(fileURLWithPath: "/tmp/s1"))
        let before = m.transcript.rows
        m.didRelaunch(EngineRelaunch(kind: .rewind, argv: ["tui", "--ndjson"], reason: ""))
        #expect(m.transcript.rows == before)
        #expect(m.phase == .starting)
    }

    // MARK: exit

    @Test func busyClearsOnExit() {
        var m = running()
        m.apply(.prompt("x"))
        #expect(m.composer.canStop)
        let exit = EngineExit(code: 9, message: "exited with code 9")
        m.didExit(exit, directory: nil)
        #expect(!m.composer.canStop)
        #expect(!m.transcript.isBusy)
        #expect(m.phase == .ended(exit))
        #expect(m.transcript.rows.last == .system("exited with code 9"))
    }

    @Test func failedLaunchEndsTranscript() {
        var m = EngineSessionModel()
        m.didStart()
        let exit = EngineExit.launchFailure(path: "/x/ds4", reason: "no such file")
        #expect(exit.message == "could not launch /x/ds4: no such file")
        m.didExit(exit, directory: nil)
        #expect(m.phase == .ended(exit))
        #expect(!m.transcript.isBusy)
        #expect(m.transcript.loadingText == nil)
    }

    @Test func notFoundNoticeListsSearched() {
        #expect(EngineSessionPhase.notFound(["/a/ds4-dogfood"]).notFoundNotice?.contains("/a/ds4-dogfood") == true)
        #expect(EngineSessionPhase.running.notFoundNotice == nil)
    }
}
