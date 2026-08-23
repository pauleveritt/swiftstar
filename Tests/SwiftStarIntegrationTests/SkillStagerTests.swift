import Testing
import Foundation
@testable import SwiftStarAppKit

/// P8 SkillStager integration tests (design D3).
///
/// `stage` copies the resolved skills tree into `<workspace>/.swiftstar/skills/`
/// so the agent's confined `read` tool can disclose each skill's `SKILL.md` on
/// demand (progressive disclosure, D2). The copy is recursive and plain; a
/// missing `skillsDir` throws — the controller treats that as a non-fatal
/// degrade (the bootstrap still names skills the agent cannot load).
///
/// Env-guarded: run via `just integration`
/// (`SWIFTSTAR_INTEGRATION=1 swift test`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct SkillStagerTests {
    /// Build a temp skills dir with `<dir>/SKILL.md` per entry. Mirrors the
    /// shape the real superpowers skills dir ships (one subdir per skill).
    private func makeSkillsDir(_ skills: [(dir: String, body: String)]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-stager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for skill in skills {
            let dir = tmp.appendingPathComponent(skill.dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let md = """
            ---
            name: \(skill.dir)
            description: Use when staging \(skill.dir)
            ---

            # \(skill.dir)

            \(skill.body)
            """
            try md.write(to: dir.appendingPathComponent("SKILL.md"),
                         atomically: true, encoding: .utf8)
        }
        return tmp
    }

    private func makeWorkspace() throws -> URL {
        let ws = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        return ws
    }

    @Test func stageCopiesSkillTreesAndReturnsDestination() throws {
        let skillsDir = try makeSkillsDir([
            ("alpha", "Alpha body."),
            ("beta", "Beta body."),
        ])
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        defer { try? FileManager.default.removeItem(at: skillsDir) }

        let dest = try SkillStager.stage(skillsDir: skillsDir, into: workspace)

        // Compare on `.path` rather than `URL.==`: `appendingPathComponent`
        // stat-stamps `hasDirectoryPath`, so a URL built before the dir exists
        // differs under `==` from one built after — even with the same `.path`.
        let expectedPath = workspace.appendingPathComponent(".swiftstar")
            .appendingPathComponent("skills").path
        #expect(dest.path == expectedPath)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        // Each skill subdir staged with a readable SKILL.md.
        for name in ["alpha", "beta"] {
            let md = dest.appendingPathComponent(name)
                .appendingPathComponent("SKILL.md")
            #expect(FileManager.default.fileExists(atPath: md.path))
            let text = try String(contentsOf: md, encoding: .utf8)
            #expect(text.contains(name))
            #expect(text.contains("description:"))
        }
    }

    @Test func stageCopiesSupportingSiblingsNotJustSkillMd() throws {
        // The whole skill directory ships (D2), so a supporting .md sibling of
        // SKILL.md must also arrive in the staged tree.
        let skillsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-stager-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        let dir = skillsDir.appendingPathComponent("with-sibling")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "name: with-sibling\ndescription: x\n".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "references.md".write(
            to: dir.appendingPathComponent("references.md"), atomically: true, encoding: .utf8)
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        defer { try? FileManager.default.removeItem(at: skillsDir) }

        let dest = try SkillStager.stage(skillsDir: skillsDir, into: workspace)
        let sibling = dest.appendingPathComponent("with-sibling")
            .appendingPathComponent("references.md")
        #expect(FileManager.default.fileExists(atPath: sibling.path))
        #expect(try String(contentsOf: sibling, encoding: .utf8) == "references.md")
    }

    @Test func stageIsIdempotentAndReplacesExistingDestination() throws {
        // Re-staging into the same workspace must replace stale content rather
        // than layering on top of it (the brief: remove a pre-existing
        // destination first).
        let skillsDir1 = try makeSkillsDir([("alpha", "first body")])
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        defer { try? FileManager.default.removeItem(at: skillsDir1) }

        _ = try SkillStager.stage(skillsDir: skillsDir1, into: workspace)

        let skillsDir2 = try makeSkillsDir([("alpha", "second body"), ("beta", "b")])
        defer { try? FileManager.default.removeItem(at: skillsDir2) }
        let dest = try SkillStager.stage(skillsDir: skillsDir2, into: workspace)

        let alphaMD = dest.appendingPathComponent("alpha").appendingPathComponent("SKILL.md")
        #expect(try String(contentsOf: alphaMD, encoding: .utf8).contains("second body"))
        let betaMD = dest.appendingPathComponent("beta").appendingPathComponent("SKILL.md")
        #expect(FileManager.default.fileExists(atPath: betaMD.path))
    }

    @Test func stageThrowsOnMissingSkillsDirAndLeavesNoRoot() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let missing = URL(fileURLWithPath: "/tmp/swiftstar-missing-\(UUID().uuidString)")

        #expect(throws: Error.self) {
            _ = try SkillStager.stage(skillsDir: missing, into: workspace)
        }
        // A missing source degrades: no skills root is created in the workspace.
        let root = workspace.appendingPathComponent(".swiftstar")
            .appendingPathComponent("skills")
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
