import Testing
import Foundation
@testable import SwiftStarKit

struct BashDigestTests {
    @Test func smallOutputShownWhole() {
        let out = CommandOutput(stdout: "hello\n", stderr: "", exit: 0, timedOut: false)
        let d = BashDigest.digest(out, command: "echo hello", artifactPath: "/runs/bash-x.log")
        #expect(d.summary.hasPrefix("bash: exit 0 (Ran: echo hello)"))
        #expect(d.summary.contains("hello"))
        #expect(d.outputDigest == ToolDigest.sha256("hello\n"))
    }

    @Test func largeOutputIsBoundedAndCarriesArtifactPointer() {
        let big = String(repeating: "y", count: 10_000)
        let out = CommandOutput(stdout: big, stderr: "", exit: 0, timedOut: false)
        let d = BashDigest.digest(out, command: "yes", artifactPath: "/runs/bash-z.log")
        #expect(d.summary.utf8.count <= 8000)
        #expect(d.summary.contains("full output: /runs/bash-z.log"))
        #expect(d.summary.contains("[truncated:"))
    }

    @Test func timedOutReported() {
        let out = CommandOutput(stdout: "", stderr: "", exit: 0, timedOut: true)
        let d = BashDigest.digest(out, command: "sleep 999", artifactPath: "/runs/bash-t.log")
        #expect(d.summary.hasPrefix("bash: timed out"))
    }

    @Test func deterministicGivenSameInput() {
        let out = CommandOutput(stdout: "same", stderr: "", exit: 3, timedOut: false)
        let a = BashDigest.digest(out, command: "cmd", artifactPath: "/runs/a.log")
        let b = BashDigest.digest(out, command: "cmd", artifactPath: "/runs/a.log")
        #expect(a == b)
    }
}
