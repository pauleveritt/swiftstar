import Foundation
import Testing
@testable import SwiftStarEngine
import SwiftStarKit

/// `report <dir> --json` (AN.4) through the fake engine, which prints the
/// recorded `fixtures/engine/report.json`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct SessionReportLoaderTests {
    private static let session = URL(fileURLWithPath: "/sessions/20261013-123136-swiftstar")

    @Test func reportFromFakeEngine() async throws {
        let argv = tempPath("report-argv")
        let f = try FakeEngine(report: "report.json", extra: ["FAKE_ENGINE_ARGV_LOG": argv])
        defer { f.remove(); try? FileManager.default.removeItem(atPath: argv) }
        let text = try await SessionReportLoader.load(executable: f.script, sessionDirectory: Self.session).get()
        #expect(text.hasPrefix("**report**: 20261013-123136-swiftstar"))
        let logged = try String(contentsOfFile: argv, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(logged == ["report", Self.session.path, "--json"])
    }

    @Test func engineWithoutReportSaysUpdate() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let r = await SessionReportLoader.load(executable: f.script, sessionDirectory: Self.session)
        guard case .failure(let failure) = r else { Issue.record("expected failure: \(r)"); return }
        #expect(failure.message.contains("no `report` command"))
    }
}
