import Foundation

/// Digests arbitrary shell output. Large output is deliberately bounded and
/// recoverable through the accompanying full-output artifact.
public enum BashDigest {
    static let inlineLimit = 4000

    public static func digest(_ output: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let status = output.timedOut ? "bash: timed out" : "bash: exit \(output.exit)"
        let combined = output.stdout + output.stderr
        let body: String
        if combined.utf8.count <= inlineLimit {
            body = combined
        } else {
            body = ToolResultCondenser.condense(combined, limit: 6000)
                + "\nfull output: \(artifactPath)"
        }
        return ToolDigest(
            summary: "\(status) (Ran: \(command))\n\(body)",
            command: command,
            artifactPath: artifactPath,
            outputDigest: ToolDigest.sha256(output.stdout))
    }
}
