import CryptoKit
import Foundation

/// The model-facing product of a command run: its bounded summary, the exact
/// host-run command, the full-output artifact, and the stdout digest.
public struct ToolDigest: Equatable, Sendable {
    public let summary: String
    public let command: String
    public let artifactPath: String
    public let outputDigest: String

    public init(summary: String, command: String, artifactPath: String, outputDigest: String) {
        self.summary = summary
        self.command = command
        self.artifactPath = artifactPath
        self.outputDigest = outputDigest
    }

    /// SHA-256 of a UTF-8 string, in the wire's prefixed lowercase-hex form.
    public static func sha256(_ string: String) -> String {
        "sha256:" + SHA256.hash(data: Data(string.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
