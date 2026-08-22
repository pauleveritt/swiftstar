import Foundation

public enum EngineFailure: Equatable, Sendable {
    case engineMissing(URL)
    case portInUse(Int)
    case instanceLocked
    case exited(code: Int32, stderrTail: String)
    case timeout
}

public enum SupervisorState: Equatable, Sendable {
    case stopped
    case starting
    case ready
    case generating
    case stopping
    case failed(EngineFailure)
}

public enum SupervisorEvent: Equatable, Sendable {
    case launchRequested
    case engineMissing(URL)
    case stderrLine(String)
    case generationStarted
    case generationFinished
    case exit(Int32)
    case stopRequested
    case timeoutFired
}

/// Pure transition function: all supervisor policy lives here, tested in
/// milliseconds. The app holds the state and forwards events; it never makes
/// policy. `port` and `stderrTail` are inputs the harness knows but the
/// transition needs (port for `.portInUse`, tail for the failure message).
/// `port` defaults to 0 = "no port context"; only `.portInUse` uses it.
public enum Supervisor {
    public static func transition(
        from state: SupervisorState,
        event: SupervisorEvent,
        port: Int = 0,
        stderrTail: [String] = []
    ) -> SupervisorState {
        switch (state, event) {
        case (.stopped, .launchRequested), (.failed, .launchRequested):
            return .starting

        case (.stopped, .engineMissing(let url)), (.failed, .engineMissing(let url)):
            // From .failed, refresh the reason: a stale failure must not hide
            // a newly-missing binary.
            return .failed(.engineMissing(url))

        case (.starting, .stderrLine(let line)):
            let lower = line.lowercased()
            if lower.contains("another ds4 process is already running") {
                return .failed(.instanceLocked)
            }
            if lower.contains("address already in use") || lower.contains("failed to listen") {
                return .failed(.portInUse(port))
            }
            if lower.contains("listening on http") {
                return .ready
            }
            return .starting

        case (.starting, .exit(let code)):
            return .failed(.exited(code: code, stderrTail: stderrTail.joined(separator: "\n")))
        case (.starting, .timeoutFired):
            return .failed(.timeout)

        case (.ready, .generationStarted):
            return .generating
        case (.generating, .generationFinished):
            return .ready

        case (.ready, .exit(let code)), (.generating, .exit(let code)):
            return .failed(.exited(code: code, stderrTail: stderrTail.joined(separator: "\n")))

        case (.stopping, .exit):
            // The user asked to stop; the exit is expected regardless of code
            // (SIGTERM is 15). Startup-cancel and graceful stop both land here.
            return .stopped
        case (.stopping, .timeoutFired):
            return .failed(.timeout)

        // Stop is legal only from in-flight states; .stopped/.failed fall
        // through to default and stay put (no wedge, idempotent).
        case (.starting, .stopRequested), (.ready, .stopRequested),
             (.generating, .stopRequested), (.stopping, .stopRequested):
            return .stopping

        default:
            return state
        }
    }
}
