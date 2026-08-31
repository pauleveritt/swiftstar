import Foundation
import CryptoKit

/// The product of one digest: the ≤8000-byte summary the model sees, the exact
/// command the host ran, the artifact path holding the full output, and a
/// deterministic digest of the stdout stream. Pure value; `sha256` is a pure
/// function of its input so digesters are testable byte-for-byte.
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

    /// sha256 of `s` as lowercase hex with a `sha256:` prefix, matching
    /// `HostToolExecutor.bashResult`'s digest format.
    public static func sha256(_ s: String) -> String {
        "sha256:" + SHA256.hash(data: Data(s.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
