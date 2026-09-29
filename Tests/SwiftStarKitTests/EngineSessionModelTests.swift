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

    @Test func readyMovesToRunning() {
        var m = EngineSessionModel()
        m.didStart()
        #expect(m.phase == .starting)
        m.apply(.ready)
        #expect(m.phase == .running)
    }

    @Test func generatingLabelComesFromComposer() {
        var m = running()
        m.apply(.prompt("hi"))
        #expect(m.composer.label == "Working…")
        m.apply(.generating(true))
        #expect(m.composer.label == "Generating…")
    }

    @Test func willQuitMovesToQuitting() {
        var m = running()
        m.willQuit()
        #expect(m.phase == .quitting)
    }

    @Test func quittingIsActive() {
        #expect(EngineSessionPhase.quitting.isActive)
        #expect(EngineSessionPhase.starting.isActive)
        #expect(EngineSessionPhase.running.isActive)
        #expect(!EngineSessionPhase.idle.isActive)
        #expect(!EngineSessionPhase.ended(EngineExit(code: 0, message: "ended")).isActive)
        #expect(!EngineSessionPhase.notFound([]).isActive)
    }

    @Test func sendRefusedWhileQuitting() {
        var m = running()
        m.willQuit()
        let rows = m.transcript.rows
        let sent = m.send("hi")
        #expect(sent == false)
        #expect(m.transcript.rows == rows)
    }

    @Test func sendAcceptedWhileRunning() {
        var m = running()
        let sent = m.send("hi")
        #expect(sent)
        #expect(m.transcript.rows == [.user("hi")])
        #expect(m.transcript.pendingUserCount == 1)
    }

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

    @Test func composerLabels() {
        var m = EngineSessionModel()
        #expect(m.composer.label == "Not started")
        m.didStart()
        #expect(m.composer.label == "Starting…")
        m.apply(.ready)
        m.apply(.loading("mapping weights"))
        #expect(m.composer.label == "Loading model…")
        let a = m.send("a")
        let b = m.send("b")
        #expect(a && b)
        #expect(m.composer.label == "Loading model… · 2 queued")
        m.apply(.awaitingInput)
        #expect(m.composer.label == "Ready")
        #expect(m.composer.canSend && m.composer.canType && !m.composer.canStop)
        m.apply(.prompt("a"))
        #expect(m.composer.label == "Working…")
        #expect(!m.composer.canSend && m.composer.canStop)
        m.willQuit()
        #expect(m.composer.label == "Ending…")
        #expect(!m.composer.canType)
        let exit = EngineExit(code: 0, message: "ended")
        m.didExit(exit, directory: nil)
        #expect(m.composer.label == "ended")
        var nf = EngineSessionModel()
        nf.didNotFind(searched: ["/x"])
        #expect(nf.composer.label == "ds4-dogfood not found")
    }

    @Test func failedLaunchEndsTranscript() {
        var m = EngineSessionModel()
        m.didStart()
        let exit = EngineExit.launchFailure(path: "/x/ds4", reason: "no such file")
        #expect(exit.message == "could not launch /x/ds4: no such file")
        m.didFailToLaunch(exit)
        #expect(m.phase == .ended(exit))
        #expect(!m.transcript.isBusy)
        #expect(m.transcript.loadingText == nil)
    }
}
