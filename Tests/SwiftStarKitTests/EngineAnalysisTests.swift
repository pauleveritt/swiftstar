import Testing
import Foundation
@testable import SwiftStarKit

/// AN.2: the session directory, and the analysis's fork, prompt and return.
struct EngineAnalysisTests {
    private static let main = URL(fileURLWithPath: "/s/20261013-112927-swiftstar")
    private static let source = URL(fileURLWithPath: "/repo")

    private func pause(capture: String? = "/s/20261013-112927-swiftstar/run-1.partial.json") -> EngineEvent {
        .pause(PauseMetrics(prefillTokens: 10, prefillMs: 5, evalCount: 1, evalMs: 5, capturePath: capture))
    }

    private func answer(_ m: inout EngineSessionModel, _ text: String) {
        _ = m.send(text)
        m.apply(.prompt(text))
        m.apply(pause())
        m.apply(.answer(EngineAnswer(text: "ok", contextUsed: 10, contextSize: 100, durationMs: 1)))
        m.apply(.awaitingInput)
    }

    /// Running, idle at `input`, with `n` answered prompts and a directory.
    private func idle(prompts n: Int = 1) -> EngineSessionModel {
        var m = EngineSessionModel()
        m.didStart()
        m.apply(.ready)
        m.apply(.awaitingInput)
        for i in 0..<n { answer(&m, "p\(i)") }
        return m
    }

    private func resumed(turns n: Int) -> EngineEvent {
        .resumed(EngineResumed(
            sessionID: Self.main.lastPathComponent,
            turns: (0..<n).map { .init(prompt: "p\($0)", answer: "ok", stopped: false) },
            rewoundTo: nil, filesChanged: nil, contextUsed: nil))
    }

    /// Idle in the fork, at `input`, before the analysis prompt is taken.
    private func forked() -> EngineSessionModel {
        var m = idle(prompts: 2)
        let r = m.beginAnalysis(report: "R", source: Self.source)!
        m.didRelaunch(r)
        m.apply(.ready)
        m.apply(resumed(turns: 2))
        m.apply(.awaitingInput)
        return m
    }

    @Test func directoryFromFirstCheckpoint() throws {
        var m = EngineSessionModel()
        m.didStart()
        for e in try Fixtures.events("tool-read.ndjson") { m.apply(e) }
        #expect(m.sessionDirectory?.lastPathComponent == "20261013-112927-swiftstar")
    }

    @Test func relaunchClearsDirectory() {
        var m = idle()
        #expect(m.sessionDirectory != nil)
        m.didRelaunch(EngineRelaunch(kind: .rewind, argv: ["tui"], reason: ""))
        #expect(m.sessionDirectory == nil)
    }

    @Test func canAnalyzeWhenIdleWithDirectory() {
        #expect(idle().canAnalyze)
    }

    @Test func cannotAnalyzeWhileBusy() {
        var m = idle()
        _ = m.send("more")
        m.apply(.prompt("more"))
        #expect(!m.canAnalyze)
    }

    @Test func cannotAnalyzeWithQueuedPrompt() {
        var m = idle()
        _ = m.send("queued")
        #expect(!m.canAnalyze)
    }

    @Test func cannotAnalyzeWithoutDirectory() {
        var m = EngineSessionModel()
        m.didStart()
        m.apply(.ready)
        m.apply(.awaitingInput)
        #expect(!m.canAnalyze)
    }

    /// SU.17, finding 1: what a report is made for goes stale with a new
    /// turn, even once Analyze is offered again, and with another session.
    @Test func theAnalysisTargetGoesStale() {
        var m = idle()
        let target = m.analysisTarget
        #expect(target?.directory.lastPathComponent == Self.main.lastPathComponent)
        answer(&m, "p1")
        #expect(m.canAnalyze)
        #expect(m.analysisTarget != nil && m.analysisTarget != target)
        var other = idle()
        other.didRelaunch(EngineRelaunch(kind: .rewind, argv: ["tui"], reason: ""))
        other.apply(.ready)
        other.apply(.awaitingInput)
        other.apply(pause(capture: "/s/20261014-000000-other/run-1.partial.json"))
        #expect(other.analysisTarget?.directory != target?.directory)
    }

    @Test func beginAnalysisReturnsForkRelaunch() {
        var m = idle()
        let r = m.beginAnalysis(report: "R", source: Self.source)
        #expect(r?.kind == .resume)
        #expect(r?.argv == ["tui", "--ndjson", "--resume", Self.main.lastPathComponent, "--source", "/repo"])
        guard case .forking(let main, let report)? = m.analysis?.stage else {
            Issue.record("not forking: \(String(describing: m.analysis))"); return
        }
        #expect(main.path == Self.main.path)
        #expect(report == "R")
        #expect(m.transcript.rows.last == .system("Starting analysis…"))
        let again = m.beginAnalysis(report: "R", source: Self.source)
        #expect(again == nil)
    }

    @Test func forkResumedStartsAnalyzing() {
        let m = forked()
        #expect(m.transcript.rows.first == .divider("Analysis — a copy of this session"))
        guard case .analyzing(let main, _, _, let sent)? = m.analysis?.stage else {
            Issue.record("not analyzing: \(String(describing: m.analysis))"); return
        }
        #expect(main.path == Self.main.path)
        #expect(!sent)
    }

    @Test func analysisPromptOnceAtInput() {
        var m = idle(prompts: 2)
        m.didRelaunch(m.beginAnalysis(report: "R", source: Self.source)!)
        m.apply(.ready)
        m.apply(resumed(turns: 2))
        let early = m.takeAnalysisPrompt()
        #expect(early == nil)  // not at input yet
        m.apply(.awaitingInput)
        let p = m.takeAnalysisPrompt()
        #expect(p?.text.contains("R") == true)
        #expect(p?.text.contains("Explain each flagged step") == true)
        #expect(p?.shown == "Analyze the session report above")
        #expect(m.transcript.rows.last == .report("R"))
        let twice = m.takeAnalysisPrompt()
        #expect(twice == nil)
    }

    @Test func doneResumesMain() {
        var m = forked()
        _ = m.takeAnalysisPrompt()
        #expect(m.analysisDoneCommand == "/resume 20261013-112927-swiftstar")
    }

    @Test func doneOnlyOnceAndOnlyIdle() {
        var m = forked()
        let p = m.takeAnalysisPrompt()!
        _ = m.send(p.text, shown: p.shown)
        m.apply(.prompt(p.text))
        #expect(m.analysisDoneCommand == nil)  // busy
        m.apply(.answer(EngineAnswer(text: "ok", contextUsed: 10, contextSize: 100, durationMs: 1)))
        m.apply(.awaitingInput)
        #expect(m.analysisDoneCommand != nil)
        m.markAnalysisReturning()
        #expect(m.analysisDoneCommand == nil)
    }

    @Test func returnResumedEndsAnalysis() {
        var m = forked()
        _ = m.takeAnalysisPrompt()
        m.markAnalysisReturning()
        m.didRelaunch(EngineRelaunch(kind: .resume, argv: ["tui"], reason: ""))
        m.apply(.ready)
        m.apply(resumed(turns: 3))
        #expect(m.transcript.rows.first == .divider("Analysis ended — back at prompt 3"))
        #expect(m.analysis == nil)
    }

    @Test func otherRelaunchEndsAnalysis() {
        var m = forked()
        m.didRelaunch(EngineRelaunch(kind: .model, argv: ["tui", "--model-id", "x"], reason: ""))
        m.apply(.ready)
        m.apply(resumed(turns: 2))
        #expect(m.transcript.rows.first == .divider("Switched to x: new conversation, files kept"))
        #expect(m.analysis == nil)
    }


    /// The controller quits the main session before starting the fork: that
    /// exit must not end the analysis.
    @Test func mainSessionExitKeepsForking() {
        var m = idle()
        _ = m.beginAnalysis(report: "R", source: Self.source)
        m.didExit(EngineExit(code: 0, message: "ended"), directory: nil)
        #expect(m.analysis != nil)
    }

    /// SU.17, finding 9: the fork's relaunch is skipped, so the analysis is
    /// abandoned, saying the main session is unchanged; once is enough.
    @Test func aSkippedRelaunchAbandonsTheAnalysis() {
        var m = idle()
        _ = m.beginAnalysis(report: "R", source: Self.source)
        m.didExit(EngineExit(code: -1, message: "did not exit"), directory: nil)
        m.abandonAnalysisTransition()
        #expect(m.analysis == nil)
        #expect(m.transcript.rows.last == .system(EngineAnalysis.mainUnchanged(Self.main)))
        let rows = m.transcript.rows.count
        m.abandonAnalysisTransition()
        #expect(m.transcript.rows.count == rows)
    }

    /// The fork's process dies before `resumed`: the analysis ends, and
    /// (final review, Important 1) says the main session is untouched and how
    /// to resume it.
    @Test func aFailedForkEndsTheAnalysisAndNamesTheMainSession() {
        var m = idle()
        let fork = m.beginAnalysis(report: "R", source: Self.source)!
        m.didExit(EngineExit(code: 0, message: "ended"), directory: nil)  // the main session quits
        m.didRelaunch(fork)
        m.didExit(EngineExit(code: 2, message: "refused"), directory: nil)  // the fork fails
        #expect(m.analysis == nil)
        #expect(m.transcript.rows.contains {
            if case .system(let s) = $0 { s.contains("20261013-112927-swiftstar") && s.contains("unchanged") } else { false } })
    }

    /// Final review, Important 2: `/resume` refused without a relaunch puts
    /// the analysis back, so Done can be tried again.
    @Test func refusedReturnKeepsAnalyzing() {
        var m = forked()
        _ = m.takeAnalysisPrompt()
        m.markAnalysisReturning()
        m.apply(.refused("session 20261013-112927-swiftstar cannot be resumed"))
        guard case .analyzing(_, _, _, true)? = m.analysis?.stage else {
            Issue.record("not analyzing: \(String(describing: m.analysis))"); return
        }
        #expect(m.analysisDoneCommand != nil)
    }

    /// Final review, Important 4: the banner waits for the fork, and Done is
    /// offered only when it would act.
    @Test func bannerOnlyOnceForkedAndDoneOnlyWhenIdle() {
        var m = idle()
        let fork = m.beginAnalysis(report: "R", source: Self.source)!
        #expect(!m.showsAnalysisBanner)
        m.didRelaunch(fork)
        m.apply(.ready)
        m.apply(resumed(turns: 1))
        #expect(m.showsAnalysisBanner)
        m.apply(.awaitingInput)
        let p = m.takeAnalysisPrompt()!
        _ = m.send(p.text, shown: p.shown)
        m.apply(.prompt(p.text))
        #expect(!m.canFinishAnalysis)
        m.apply(.answer(EngineAnswer(text: "ok", contextUsed: 10, contextSize: 100, durationMs: 1)))
        m.apply(.awaitingInput)
        #expect(m.canFinishAnalysis)
    }

    @Test func sendShownText() {
        var m = idle()
        let sent = m.send("long", shown: "short")
        #expect(sent)
        #expect(m.transcript.rows.last == .user("short"))
    }
}
