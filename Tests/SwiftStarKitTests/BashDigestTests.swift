import Foundation
import Testing
@testable import SwiftStarKit

struct BashDigestTests {
    @Test func smallOutputShownWhole() {
        let output = CommandOutput(stdout: "hello\n", stderr: "", exit: 0, timedOut: false)
        let digest = BashDigest.digest(output, command: "echo hello", artifactPath: "/runs/bash-x.log")
        #expect(digest.summary.hasPrefix("bash: exit 0 (Ran: echo hello)"))
        #expect(digest.summary.contains("hello"))
        #expect(digest.outputDigest == ToolDigest.sha256("hello\n"))
    }

    @Test func largeOutputIsBoundedAndCarriesArtifactPointer() {
        let output = CommandOutput(stdout: String(repeating: "y", count: 10_000), stderr: "", exit: 0, timedOut: false)
        let digest = BashDigest.digest(output, command: "yes", artifactPath: "/runs/bash-z.log")
        #expect(digest.summary.utf8.count <= 8000)
        #expect(digest.summary.contains("full output: /runs/bash-z.log"))
        #expect(digest.summary.contains("[truncated:"))
    }

    @Test func timedOutReported() {
        let output = CommandOutput(stdout: "", stderr: "", exit: 0, timedOut: true)
        #expect(BashDigest.digest(output, command: "sleep 999", artifactPath: "/runs/bash-t.log").summary.hasPrefix("bash: timed out"))
    }
}
