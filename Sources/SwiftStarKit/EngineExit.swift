import Foundation

/// How the engine process ended, as `Process.terminationReason` reports it.
public enum EngineTermination: Equatable, Sendable {
    /// A normal exit; the code is the exit status.
    case exit
    /// An uncaught signal; the code is the signal number.
    case signal
}

public struct EngineExit: Equatable, Sendable {
    public let code: Int32
    public let message: String

    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }

    /// `forced` means SwiftStar itself escalated to SIGKILL after the quit
    /// timed out; `terminated` that it sent SIGTERM (not escalated further);
    /// `afterProtocolError` that it ended the engine because the wire broke
    /// its protocol. All are our doing, not a crash.
    public static func describe(
        code: Int32, stderrTail: String, sawReady: Bool,
        reason: EngineTermination = .exit, forced: Bool = false, terminated: Bool = false,
        afterProtocolError: Bool = false
    ) -> EngineExit {
        if forced {
            let after = afterProtocolError ? "a protocol error" : "the quit timed out"
            return EngineExit(code: code, message: "ended by force after \(after)")
        }
        // Only our own SIGTERM's outcome reads as ours; an engine that exits on
        // its own after a bad line keeps its reason.
        if afterProtocolError, (reason == .signal && code == SIGTERM) || (reason == .exit && code == 130) {
            return EngineExit(code: code, message: "ended after a protocol error")
        }
        if reason == .signal {
            if terminated && code == SIGTERM {
                return EngineExit(code: code, message: "ended after the quit timed out")
            }
            let name = signalName(code).map { " (\($0))" } ?? ""
            return EngineExit(code: code, message: "killed by signal \(code)\(name)")
        }
        if terminated && reason == .exit && code == 130 {
            // The engine catches our SIGTERM and exits 130; that is our doing.
            return EngineExit(code: code, message: "ended after the quit timed out")
        }
        // The session directory has its own row after the exit message.
        let cleaned = stderrTail.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(EngineSessionConstants.sessionArtifactsMarker) }
            .joined(separator: "\n")
        let tail = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastLine = cleaned.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
        let message: String
        switch code {
        case 0:
            message = "ended"
        case 130:
            message = "interrupted"
        case _ where code == 2 || !sawReady:
            message = "refused to start: " + (lastLine.isEmpty ? "exit code \(code)" : lastLine)
        case 1:
            message = "Ended without a clean answer." + (tail.isEmpty ? "" : "\n\(tail)")
        default:
            message = "exited with code \(code)" + (tail.isEmpty ? "" : "\n\(tail)")
        }
        return EngineExit(code: code, message: message)
    }

    /// The process could not be launched at all: there is no exit status, so
    /// the message is the reason, not "refused to start" or an exit code.
    public static func launchFailure(path: String, reason: String) -> EngineExit {
        EngineExit(code: -1, message: "could not launch \(path): \(reason)")
    }

    private static func signalName(_ n: Int32) -> String? {
        let names: [Int32: String] = [
            1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT",
            8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE",
            14: "SIGALRM", 15: "SIGTERM",
        ]
        return names[n]
    }
}
