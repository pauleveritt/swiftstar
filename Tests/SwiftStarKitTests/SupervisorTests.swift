import Testing
import Foundation
@testable import SwiftStarKit

struct SupervisorTests {
    @Test func launchLeadsToReadyViaListening() {
        var s = Supervisor.transition(from: .stopped, event: .launchRequested)
        #expect(s == .starting)
        s = Supervisor.transition(from: s, event: .stderrLine("0822 00:00:00 ds4-server: listening on http://127.0.0.1:8000"))
        #expect(s == .ready)
    }

    @Test func generationRoundTrip() {
        var s = Supervisor.transition(from: .ready, event: .generationStarted)
        #expect(s == .generating)
        s = Supervisor.transition(from: s, event: .generationFinished)
        #expect(s == .ready)
    }

    @Test func instanceLockMapsToFailure() {
        let s = Supervisor.transition(from: .starting, event: .stderrLine("ds4: another ds4 process is already running (pid 32046); refusing to start"))
        #expect(s == .failed(.instanceLocked))
    }

    @Test func portInUseMapsToFailure() {
        let s = Supervisor.transition(from: .starting, event: .stderrLine("ds4-server: failed to listen on 127.0.0.1:8000: address already in use"), port: 8000)
        #expect(s == .failed(.portInUse(8000)))
    }

    @Test func childExitMapsToFailureWithTail() {
        let s = Supervisor.transition(
            from: .starting,
            event: .exit(1),
            stderrTail: ["ds4: cannot open model '/nope.gguf': No such file or directory"]
        )
        #expect(s == .failed(.exited(code: 1, stderrTail: "ds4: cannot open model '/nope.gguf': No such file or directory")))
    }

    @Test func timeoutMapsToFailure() {
        #expect(Supervisor.transition(from: .starting, event: .timeoutFired) == .failed(.timeout))
    }

    @Test func stopFromReadyGoesToStoppingThenStopped() {
        var s = Supervisor.transition(from: .ready, event: .stopRequested)
        #expect(s == .stopping)
        s = Supervisor.transition(from: s, event: .exit(0))
        #expect(s == .stopped)
    }

    @Test func failedCanRestart() {
        let s = Supervisor.transition(from: .failed(.timeout), event: .launchRequested)
        #expect(s == .starting)
    }

    @Test func illegalTransitionKeepsState() {
        // A generation event while stopped is a lie from the harness: keep the state.
        #expect(Supervisor.transition(from: .stopped, event: .generationFinished) == .stopped)
    }

    @Test func stopFromStoppedIsNoOp() {
        // Stop is only legal from in-flight states; a stop request while stopped
        // must not wedge the machine in .stopping with no process to terminate.
        #expect(Supervisor.transition(from: .stopped, event: .stopRequested) == .stopped)
    }

    @Test func stopFromFailedPreservesFailure() {
        let before = SupervisorState.failed(.timeout)
        #expect(Supervisor.transition(from: before, event: .stopRequested) == before)
    }

    @Test func engineMissingFromFailedRefreshesReason() {
        let url = URL(fileURLWithPath: "/nope/ds4-server")
        let s = Supervisor.transition(from: .failed(.timeout), event: .engineMissing(url))
        #expect(s == .failed(.engineMissing(url)))
    }

    @Test func stopFromStartingThenNonZeroExitIsStopped() {
        // The user asked to cancel startup; a non-zero exit during stopping is
        // the expected termination, not a failure.
        var s = Supervisor.transition(from: .starting, event: .stopRequested)
        #expect(s == .stopping)
        s = Supervisor.transition(from: s, event: .exit(15))
        #expect(s == .stopped)
    }

    @Test func lateStderrLineInFailedIsIgnored() {
        // A stderr line arriving after failure must not resurrect state.
        let before = SupervisorState.failed(.instanceLocked)
        let s = Supervisor.transition(from: before, event: .stderrLine("ds4-server: listening on http://127.0.0.1:8000"))
        #expect(s == before)
    }

    @Test func detectionIsCaseInsensitive() {
        let locked = Supervisor.transition(from: .starting, event: .stderrLine("Ds4: ANOTHER ds4 PROCESS is already running (pid 1)"))
        #expect(locked == .failed(.instanceLocked))
        let ready = Supervisor.transition(from: .starting, event: .stderrLine("DS4-SERVER: LISTENING ON HTTP://127.0.0.1:8000"))
        #expect(ready == .ready)
    }

    @Test func engineMissingMapsToFailure() {
        let url = URL(fileURLWithPath: "/nope/ds4-server")
        #expect(Supervisor.transition(from: .stopped, event: .engineMissing(url)) == .failed(.engineMissing(url)))
    }

    @Test func readySignalWhileGeneratingIsIgnored() {
        // A late "listening" line (already ready) must not reset state.
        let s = Supervisor.transition(from: .generating, event: .stderrLine("ds4-server: listening on http://127.0.0.1:8000"))
        #expect(s == .generating)
    }
}
