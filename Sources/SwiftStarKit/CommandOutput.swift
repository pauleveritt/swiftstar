import Foundation

/// The pure shape of one completed command run, decoupled from
/// `SubprocessRunner.Result` (which lives in SwiftStarAppKit so the pure
/// digesters cannot depend on it). P24.3: the input to every digester.
public struct CommandOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exit: Int32
    public let timedOut: Bool

    public init(stdout: String, stderr: String, exit: Int32, timedOut: Bool) {
        self.stdout = stdout
        self.stderr = stderr
        self.exit = exit
        self.timedOut = timedOut
    }
}
