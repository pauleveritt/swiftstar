import Foundation
import Testing
@testable import SwiftStarKit

// SU.7b: each recent project with its newest resumable conversation.
struct RecentProjectsTests {
    private static let alpha = "/Users/example/projects/alpha"
    private static let beta = "/Users/example/projects/beta"
    private static let gamma = "/Users/example/projects/gamma"
    private static let now = EngineSessionEntry.parseUpdated("2026-10-13T11:12:00")!

    private static func fixture() throws -> [EngineSessionEntry] {
        try EngineSessionEntry.decodeList(Data(contentsOf: Fixtures.root.appendingPathComponent("sessions-all.json"))).get()
    }

    private static func items(
        _ recents: [String], entries: [EngineSessionEntry], current: String? = nil,
        exists: @escaping (String) -> Bool = { _ in true }, rootOf: @escaping (URL) -> URL? = { _ in nil }
    ) -> [RecentProject] {
        RecentProjects.items(
            recents: recents, entries: entries, current: current, exists: exists, rootOf: rootOf,
            now: now, locale: Locale(identifier: "en_US"))
    }

    @Test func resumableNewestGetsItsLabel() throws {
        let rows = Self.items([Self.beta, Self.alpha], entries: try Self.fixture())
        #expect(rows.map(\.title) == ["beta", "alpha"])
        #expect(rows.first?.latest?.id == "20261013-110000-beta")
        #expect(rows.first?.latestLabel == "Add a menu · 12m ago")
    }

    @Test func nonResumableNewestIsSkipped() throws {
        let rows = Self.items([Self.beta], entries: try Self.fixture())
        #expect(rows.first?.latest != nil)
        #expect(rows.first?.latest?.id != "20261013-120000-beta")
    }

    @Test func noEntriesNoLabel() throws {
        let rows = Self.items([Self.gamma], entries: try Self.fixture())
        #expect(rows.first?.latest == nil)
        #expect(rows.first?.latestLabel == nil)
    }

    @Test func currentIsCheckedWithoutLatest() throws {
        let rows = Self.items([Self.beta, Self.alpha], entries: try Self.fixture(), current: Self.beta)
        #expect(rows.map(\.isCurrent) == [true, false])
        #expect(rows.first?.latest == nil)
        #expect(rows.last?.latest?.id == "20261012-090000-alpha")
    }

    @Test func missingFolderIsDisabled() throws {
        let rows = Self.items([Self.beta], entries: try Self.fixture(), exists: { _ in false })
        #expect(rows.first?.disabledReason == "folder not found")
        #expect(rows.first?.latest == nil)
    }

    @Test func subfolderUsesItsRoot() throws {
        let rows = Self.items(
            [Self.beta + "/Sources"], entries: try Self.fixture(),
            rootOf: { $0.path.hasPrefix(Self.beta) ? URL(fileURLWithPath: Self.beta) : nil })
        #expect(rows.first?.title == "Sources")
        #expect(rows.first?.latest?.id == "20261013-110000-beta")
    }

    @Test func privateMatchesVar() throws {
        // The engine records the path the session started from, unresolved
        // (`/var/folders/…`); the app may hold the resolved form.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("su7b-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let resolved = URL(fileURLWithPath: realpath(folder.path, nil).map { p in
            defer { free(p) }
            return String(cString: p)
        } ?? folder.path)
        #expect(resolved.path != folder.path)
        let entry = EngineSessionEntry(
            id: "x", path: "/s/x", source: folder.path, updated: Self.now, prompts: 1, firstPrompt: "Hi",
            resumable: true)
        let rows = Self.items([resolved.path], entries: [entry])
        #expect(rows.first?.latest?.id == "x")
    }

    @Test func longTitleIsCut() {
        let title = String(repeating: "abcdefghij", count: 6)
        let entry = EngineSessionEntry(
            id: "x", path: "/s/x", source: Self.alpha, updated: Self.now, prompts: 1, firstPrompt: title,
            resumable: true)
        let label = Self.items([Self.alpha], entries: [entry]).first?.latestLabel ?? ""
        #expect(label.hasPrefix(String(title.prefix(40)) + "… · "))
    }
}
