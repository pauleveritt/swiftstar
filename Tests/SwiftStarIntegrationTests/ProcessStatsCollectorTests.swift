import Testing
import Foundation
@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct ProcessStatsCollectorTests {
    @Test func collectReturnsSanitizedSnapshot() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["2"]
        try process.run()
        defer { process.terminate() }

        let collector = ProcessStatsCollector()
        let snap = await collector.collect(pid: process.processIdentifier)
        #expect(snap.residentBytes != nil)
        #expect((snap.residentBytes ?? 0) > 0)
        #expect(snap.watts >= 0 && snap.watts.isFinite)
        #expect(snap.gpuUtilization >= 0 && snap.gpuUtilization <= 100)
        #expect(snap.cpuUtilization >= 0 && snap.cpuUtilization <= 100)
    }

    @Test func collectWithoutPidReturnsNilResident() async {
        let collector = ProcessStatsCollector()
        let snap = await collector.collect(pid: nil)
        #expect(snap.residentBytes == nil)
        #expect(snap.watts >= 0 && snap.watts.isFinite)
    }
}
