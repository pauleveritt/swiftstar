import Foundation
import Testing
@testable import SwiftStarEngine
import SwiftStarKit

/// Runs the bundled `session_last.py` (AN.2) against a recorded session.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct SessionReportLoaderTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let session = repoRoot.appendingPathComponent("fixtures/sessions/20261013-123136-swiftstar")

    @Test func reportFromFixtureSession() async throws {
        let text = try await SessionReportLoader.load(sessionDirectory: Self.session).get()
        #expect(text.hasPrefix("**last**: 20261013-123136-swiftstar"))
    }

    @Test func bundledScriptExists() throws {
        let script = try #require(SessionReportLoader.bundledScript)
        #expect(FileManager.default.fileExists(atPath: script.path))
    }

    @Test func missingScriptFails() async {
        let r = await SessionReportLoader.load(
            sessionDirectory: Self.session, script: URL(fileURLWithPath: "/nonexistent/session_last.py"))
        guard case .failure(let f) = r else { Issue.record("expected failure: \(r)"); return }
        #expect(f.message.contains("not found"))
    }

    @Test func badSessionFails() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("an2-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let r = await SessionReportLoader.load(sessionDirectory: empty)
        guard case .failure(let f) = r else { Issue.record("expected failure: \(r)"); return }
        #expect(f.message.contains("receipt.json"))
    }
}
