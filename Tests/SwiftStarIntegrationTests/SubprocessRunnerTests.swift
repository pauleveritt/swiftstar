import Testing
import Foundation
@testable import SwiftStarAppKit

/// Item 3 (P22 cleanup): `SubprocessRunner.run` gained an async twin that
/// waits by yielding (`Task.sleep`) instead of blocking the calling thread
/// (`Thread.sleep`) — the two MainActor call sites (AgentController's host
/// `bash` tool, `WorktreeDispatcher`'s async `runValidation`) used to freeze
/// the whole app's UI for up to the timeout. Real subprocesses, so this suite
/// is integration-tier gated like its siblings (`just integration`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct SubprocessRunnerTests {
    private let tmp = FileManager.default.temporaryDirectory

    @Test func syncRunCapturesStdoutAndExit() throws {
        let r = try SubprocessRunner.run("echo hello-sync", in: tmp)
        #expect(r.exit == 0)
        #expect(r.stdout.contains("hello-sync"))
        #expect(!r.timedOut)
    }

    @Test func directArgvRunDoesNotReparseArgumentsThroughShell() throws {
        let r = try SubprocessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "literal; echo should-not-run"],
            in: tmp)
        #expect(r.exit == 0)
        #expect(r.stdout == "literal; echo should-not-run")
    }

    @Test func syncRunCapturesNonZeroExitAndStderr() throws {
        let r = try SubprocessRunner.run(">&2 echo boom; exit 3", in: tmp)
        #expect(r.exit == 3)
        #expect(r.stderr.contains("boom"))
    }

    @Test func syncRunTimesOutOnAHangingCommand() throws {
        let r = try SubprocessRunner.run("sleep 5", in: tmp, timeout: 0.2)
        #expect(r.timedOut)
    }

    @Test func asyncRunCapturesStdoutAndExit() async throws {
        let r = try await SubprocessRunner.run("echo hello-async", in: tmp)
        #expect(r.exit == 0)
        #expect(r.stdout.contains("hello-async"))
        #expect(!r.timedOut)
    }

    @Test func asyncRunCapturesNonZeroExitAndStderr() async throws {
        let r = try await SubprocessRunner.run(">&2 echo boom-async; exit 3", in: tmp)
        #expect(r.exit == 3)
        #expect(r.stderr.contains("boom-async"))
    }

    @Test func asyncRunTimesOutOnAHangingCommand() async throws {
        let r = try await SubprocessRunner.run("sleep 5", in: tmp, timeout: 0.2)
        #expect(r.timedOut)
    }

    /// The point of the async overload: it must not block a thread while it
    /// waits. Running N of them concurrently proves it — a blocking
    /// implementation (`Thread.sleep` under the hood, e.g. a fake "async" that
    /// just wraps the sync version in a `Task`) would tie up one thread per
    /// call, and once concurrent calls exceed the cooperative pool's thread
    /// count they'd start serializing, pushing the total wall time toward
    /// N × the command's own duration. The real implementation waits via
    /// `Task.sleep`, which is just a scheduled resumption (no thread pinned),
    /// so N concurrent calls finish in roughly one command's duration
    /// regardless of N. A generous margin (well under N × duration) keeps this
    /// tolerant of a busy CI machine while still catching a regression to a
    /// thread-blocking implementation.
    @Test func asyncRunDoesNotSerializeConcurrentCalls() async throws {
        let n = 8
        let start = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<n {
                group.addTask {
                    _ = try await SubprocessRunner.run("sleep 0.3", in: self.tmp)
                }
            }
            try await group.waitForAll()
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 2.0,
            "\(n) concurrent 0.3s async runs took \(elapsed)s — expected roughly 0.3s if truly concurrent, not \(Double(n) * 0.3)s serialized")
    }
}
