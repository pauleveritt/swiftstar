import Foundation
import Testing
@testable import SwiftStarEngine

/// SU.16, D3: the candidate worktree from a session's `receipt.json`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct ReceiptReaderTests {
    private static let sessions = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sessions")

    /// A session directory whose receipt is the recorded one, with
    /// `worktree_path` pointed at `worktree`.
    private static func session(worktree: String?, receipt: String = "20261018-112154-su-ui") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: sessions.appendingPathComponent("\(receipt)/receipt.json"))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["worktree_path"] = worktree
        try JSONSerialization.data(withJSONObject: object).write(to: dir.appendingPathComponent("receipt.json"))
        return dir
    }

    @Test(arguments: ["20261013-123136-swiftstar", "20261018-112154-su-ui"])
    func worktreeFromTheRecordedReceipt(_ name: String) throws {
        let worktree = FileManager.default.temporaryDirectory.appendingPathComponent("candidate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktree) }
        let dir = try Self.session(worktree: worktree.path, receipt: name)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ReceiptReader.worktree(sessionDirectory: dir)?.standardizedFileURL == worktree.standardizedFileURL)
    }

    @Test func recordedWorktreeIsGoneSoNil() {
        // As recorded: the engine removed its temp worktree when the session ended.
        #expect(ReceiptReader.worktree(sessionDirectory: Self.sessions.appendingPathComponent("20261018-112154-su-ui")) == nil)
    }

    @Test func noReceiptOrNoKeyIsNil() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("receipt-none-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(ReceiptReader.worktree(sessionDirectory: empty) == nil)
        let noKey = try Self.session(worktree: nil)
        defer { try? FileManager.default.removeItem(at: noKey) }
        #expect(ReceiptReader.worktree(sessionDirectory: noKey) == nil)
    }
}
