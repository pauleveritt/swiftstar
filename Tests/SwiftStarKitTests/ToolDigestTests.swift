import Foundation
import Testing
@testable import SwiftStarKit

struct ToolDigestTests {
    @Test func commandOutputCarriesStreamsAndVerdict() {
        let out = CommandOutput(stdout: "o", stderr: "e", exit: 1, timedOut: false)
        #expect(out.stdout == "o")
        #expect(out.stderr == "e")
        #expect(out.exit == 1)
        #expect(!out.timedOut)
    }

    @Test func sha256IsDeterministicAndPrefixed() {
        let a = ToolDigest.sha256("hello")
        #expect(a == ToolDigest.sha256("hello"))
        #expect(a.hasPrefix("sha256:"))
        #expect(a != ToolDigest.sha256("world"))
        #expect(a.count == "sha256:".count + 64)
    }

    @Test func toolDigestCarriesAllFields() {
        let digest = ToolDigest(summary: "s", command: "c", artifactPath: "p", outputDigest: "h")
        #expect(digest.summary == "s")
        #expect(digest.command == "c")
        #expect(digest.artifactPath == "p")
        #expect(digest.outputDigest == "h")
    }
}
