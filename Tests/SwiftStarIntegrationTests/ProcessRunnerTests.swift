import Foundation
import Testing
@testable import SwiftStarEngine

// SU.6g, D4: the runner waits only as long as something is happening.
@Suite(.serialized, .integration, .tags(.integration), .timeLimit(.minutes(1)))
struct ProcessRunnerTests {
    /// A child that dies on SIGTERM ends the call soon after the timeout,
    /// not a fixed second later.
    @Test func aTimedOutChildThatDiesOnTermEndsPromptly() async {
        let start = ContinuousClock.now
        let result = await ProcessRunner.run(executable: "/bin/sleep", arguments: ["30"], timeout: .milliseconds(300))
        let elapsed = ContinuousClock.now - start
        #expect(result.failureValue == .timedOut)
        #expect(elapsed < .milliseconds(900), "took \(elapsed)")
    }

    /// A child that exits while a background grandchild holds its stdout
    /// returns its output after the drain, not at the timeout.
    @Test func aGrandchildHoldingThePipeDoesNotStretchTheCall() async throws {
        let start = ContinuousClock.now
        let result = await ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "echo hi; sleep 30 & exit 0"], timeout: .seconds(10))
        let elapsed = ContinuousClock.now - start
        let output = try #require(result.successValue)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hi\n")
        #expect(output.code == 0)
        #expect(elapsed < .seconds(2), "took \(elapsed)")
    }
}

private extension Result {
    var successValue: Success? { if case .success(let s) = self { s } else { nil } }
    var failureValue: Failure? { if case .failure(let f) = self { f } else { nil } }
}
