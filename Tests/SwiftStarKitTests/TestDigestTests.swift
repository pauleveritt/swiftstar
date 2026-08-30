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

    @Test func pytestJSONClustersAndCarriesPassedCount() {
        let json = """
        {"summary":{"passed":10,"failed":3,"error":0,"skipped":1},
         "tests":[
           {"nodeid":"tests/test_api.py::test_create_user","outcome":"failed","call":{"longrepr":"def test_create_user():\\n    r = client.post(\\nE   AssertionError: expected 201, got 500\\n"}},
           {"nodeid":"tests/test_api.py::test_delete_user","outcome":"failed","call":{"longrepr":"def test_delete_user():\\nE   AssertionError: expected 201, got 500\\n"}},
           {"nodeid":"tests/test_db.py::test_migration","outcome":"failed","call":{"longrepr":"def test_migration():\\nE   OperationalError: no such table\\n"}},
           {"nodeid":"tests/test_api.py::test_ok","outcome":"passed","call":{"longrepr":""}}
         ]}
        """
        let out = CommandOutput(stdout: json, stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "uv run pytest", artifactPath: "/runs/test-d.log")
        #expect(d.summary.contains("test: 10 passed, 3 failed (exit 1)"))
        #expect(d.summary.contains("[1] tests/test_api.py — 2 failures"))
        #expect(d.summary.contains("[2] tests/test_db.py — 1 failure"))
        #expect(d.summary.contains("AssertionError: expected 201, got 500"))
        #expect(d.summary.contains("Ran: uv run pytest"))
    }

    @Test func nonJSONStdoutFallsBackToText() {
        // A crashed runner wrote a traceback, not JSON — the XCTest text path
        // finds nothing, but the digester is total and reports honestly.
        let traceback = "Traceback (most recent call last):\n  File \"/usr/lib/runner.py\", line 9\nRuntimeError: boom\n"
        let out = CommandOutput(stdout: traceback, stderr: "", exit: 1, timedOut: false)
        let d = TestDigest.digest(out, command: "uv run pytest", artifactPath: "/runs/test-e.log")
        #expect(d.summary.contains("no failures parsed"))
        #expect(d.summary.contains("full output: /runs/test-e.log"))
    }
}
