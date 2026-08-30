import Foundation

/// The single direct-argv entry point for git helpers.
///
/// Git is deliberately kept separate from the shell-command overload: paths,
/// refs, and user-authored packet values must reach git as individual argv
/// elements, not be interpolated into a shell string. Callers still decide
/// whether a non-zero exit is an infrastructure error or a domain result.
public enum GitProcess {
    public static let executable = URL(fileURLWithPath: "/usr/bin/git")

    @discardableResult
    public static func run(
        _ arguments: [String],
        in directory: URL,
        timeout: TimeInterval = 300
    ) throws -> SubprocessRunner.Result {
        try SubprocessRunner.run(
            executable: executable,
            arguments: ["-C", directory.path] + arguments,
            in: directory,
            timeout: timeout)
    }
}
