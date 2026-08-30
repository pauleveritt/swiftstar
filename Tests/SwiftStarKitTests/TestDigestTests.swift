import Testing
import Foundation
@testable import SwiftStarKit

struct TestDigestTests {
    /// Three `swift test` failures; two share (file, message) so the clusters
    /// are [2, 1].
    private static let xctestSample = """
    Test Suite 'All tests' started at 2026-08-30 12:00:00
    Test Case '-[SwiftStarKitTests.FooTests testBar]' started.
    /tmp/foo/FooTests.swift:42: error: -[SwiftStarKitTests.FooTests testBar] : XCTAssertEqual failed: ("1") is not equal to ("2")
    Test Case '-[SwiftStarKitTests.FooTests testBar]' failed (0.123 seconds).
    /tmp/foo/FooTests.swift:51: error: -[SwiftStarKitTests.FooTests testBaz] : XCTAssertEqual failed: ("3") is not equal to ("4")
    Test Case '-[SwiftStarKitTests.FooTests testBaz]' failed (0.050 seconds).
    /tmp/foo/FooTests.swift:63: error: -[SwiftStarKitTests.FooTests testBar] : XCTAssertEqual failed: ("1") is not equal to ("2")
    Test Case '-[SwiftStarKitTests.FooTests testBar]' failed (0.020 seconds).
    Test Suite 'All tests' finished at 2026-08-30 12:00:01
    """

    @Test func xctestClustersByFileAndMessage() {
        let out = CommandOutput(stdout: Self.xctestSample, stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "swift test", artifactPath: "/runs/test-a.log")
        #expect(d.summary.contains("3 failures in 2 clusters"))
        #expect(d.summary.contains("[1] FooTests.swift — 2 failures"))
        #expect(d.summary.contains("[2] FooTests.swift — 1 failure"))
        #expect(d.summary.contains("XCTAssertEqual failed: (\"1\") is not equal to (\"2\")"))
        #expect(d.summary.contains("(FooTests.swift:42)"))
        #expect(d.summary.hasPrefix("test:"))
        #expect(d.summary.contains("Ran: swift test"))
        #expect(d.summary.contains("full output: /runs/test-a.log"))
    }

    @Test func xctestAllPassedWhenExitZeroAndNoFailures() {
        let out = CommandOutput(stdout: "Test Suite 'All tests' finished\n", stderr: "", exit: 0, timedOut: false)
        let d = TestDigest.digest(out, command: "swift test", artifactPath: "/runs/test-b.log")
        #expect(d.summary.contains("all passed"))
    }

    @Test func condenseIsANoopForPathologicalRun() {
        var lines = ["Test Suite 'All tests' started"]
        for i in 0..<150 {
            lines.append("/tmp/f/F\(i).swift:\(i): error: -[T.F\(i) test\(i)] : boom \(i)")
        }
        let out = CommandOutput(stdout: lines.joined(separator: "\n"), stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "swift test", artifactPath: "/runs/test-c.log")
        #expect(ToolResultCondenser.condense(d.summary) == d.summary)
        #expect(d.summary.utf8.count <= 8000)
    }
}
