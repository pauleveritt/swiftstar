import Testing
import Foundation
@testable import SwiftStarKit

struct SuperpowersBootstrapTests {
    /// One skill staged into a temp skills dir: `(dirName, name, rawDescription)`.
    /// `rawDescription` is written verbatim after `description: ` (the real
    /// brainstorming skill ships its description quoted, so the parser must strip
    /// a single surrounding `"` pair).
    private func makeSkillsDir(_ skills: [(dir: String, name: String, raw: String)]) -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-skills-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for skill in skills {
            let dir = tmp.appendingPathComponent(skill.dir)
            try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let md = """
            ---
            name: \(skill.name)
            description: \(skill.raw)
            ---

            # \(skill.name)

            Body text that must not be scanned for name:/description:.
            """
            try! md.write(to: dir.appendingPathComponent("SKILL.md"),
                          atomically: true, encoding: .utf8)
        }
        return tmp
    }

    /// Strip a single surrounding `"` pair (mirrors the parser's quote handling).
    private func clean(_ s: String) -> String {
        var v = s
        if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    /// The 14 real superpowers skills, front-matter mirrored from the skills dir.
    private let realSkills: [(dir: String, name: String, raw: String)] = [
        ("brainstorming", "brainstorming",
         "\"You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation.\""),
        ("dispatching-parallel-agents", "dispatching-parallel-agents",
         "Use when facing 2+ independent tasks that can be worked on without shared state or sequential dependencies"),
        ("executing-plans", "executing-plans",
         "Use when you have a written implementation plan to execute in a separate session with review checkpoints"),
        ("finishing-a-development-branch", "finishing-a-development-branch",
         "Use when implementation is complete, all tests pass, and you need to decide how to integrate the work"),
        ("receiving-code-review", "receiving-code-review",
         "Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation"),
        ("requesting-code-review", "requesting-code-review",
         "Use when completing tasks, implementing major features, or before merging to verify work meets requirements"),
        ("subagent-driven-development", "subagent-driven-development",
         "Use when executing implementation plans with independent tasks in the current session"),
        ("systematic-debugging", "systematic-debugging",
         "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes"),
        ("test-driven-development", "test-driven-development",
         "Use when implementing any feature or bugfix, before writing implementation code"),
        ("using-git-worktrees", "using-git-worktrees",
         "Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback"),
        ("using-superpowers", "using-superpowers",
         "Use when starting any conversation - establishes how to find and use skills, requiring skill invocation before ANY response including clarifying questions"),
        ("verification-before-completion", "verification-before-completion",
         "Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always"),
        ("writing-plans", "writing-plans",
         "Use when you have a spec or requirements for a multi-step task, before touching code"),
        ("writing-skills", "writing-skills",
         "Use when creating new skills, editing existing skills, or verifying skills work before deployment"),
    ]

    private static let header =
        "You have Superpowers skills available. Load one before the work it covers."
    private static let disclosure =
        "To load a skill, read its SKILL.md inside the workspace (.swiftstar/skills/<name>/SKILL.md)."

    @Test func skillNamesContainsAllFourteenSorted() {
        let dir = makeSkillsDir(realSkills)
        let boot = SuperpowersBootstrap.build(skillsDir: dir)
        let expected = realSkills.map { $0.name }.sorted()
        #expect(boot.skillNames == expected)
        #expect(boot.skillNames.count == 14)
    }

    @Test func indexPromptHasHeaderAndDisclosure() {
        let dir = makeSkillsDir(realSkills)
        let prompt = SuperpowersBootstrap.build(skillsDir: dir).indexPrompt
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count >= 2)
        #expect(lines[0] == Self.header)
        #expect(lines[1] == Self.disclosure)
    }

    @Test func indexLinesAreSortedByNameWithDescriptions() {
        let dir = makeSkillsDir(realSkills)
        let prompt = SuperpowersBootstrap.build(skillsDir: dir).indexPrompt
        let skillLines = prompt.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("- ") }
        // Each rendered line: "- <name>: <cleanDescription>", in name-sorted order.
        let expected = realSkills.sorted { $0.name < $1.name }
            .map { "- \($0.name): \(clean($0.raw))" }
        #expect(skillLines == expected)
    }

    @Test func brainstormingDescriptionIsUnquoted() {
        // The quoted brainstorming description must ship unquoted in the index.
        let dir = makeSkillsDir(realSkills)
        let prompt = SuperpowersBootstrap.build(skillsDir: dir).indexPrompt
        let expected = "- brainstorming: You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."
        #expect(prompt.contains(expected))
        #expect(!prompt.contains("\""))  // no stray quotes leak into the index
    }

    @Test func buildIsDeterministic() {
        let dir = makeSkillsDir(realSkills)
        let a = SuperpowersBootstrap.build(skillsDir: dir)
        let b = SuperpowersBootstrap.build(skillsDir: dir)
        #expect(a.indexPrompt == b.indexPrompt)
        #expect(a.skillNames == b.skillNames)
    }

    @Test func missingDirDegradesToNoSkills() {
        let dir = URL(fileURLWithPath: "/tmp/does-not-exist-swiftstar-\(UUID().uuidString)")
        let boot = SuperpowersBootstrap.build(skillsDir: dir)
        #expect(boot.skillNames == [])
        #expect(boot.indexPrompt == "No skills available in this workspace.")
    }

    @Test func emptyDirDegradesToNoSkills() {
        // Dir exists but has no skill subdirs → same degrade as missing.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-empty-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let boot = SuperpowersBootstrap.build(skillsDir: tmp)
        #expect(boot.skillNames == [])
        #expect(boot.indexPrompt == "No skills available in this workspace.")
    }

    @Test func fallsBackToDirNameWhenNameAndDescriptionAbsent() {
        // A SKILL.md with no front-matter: name and description both fall back to
        // the directory name.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-nofm-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dir = tmp.appendingPathComponent("mystery")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = """
        # Just a title, no front-matter.

        Body only.
        """
        try! md.write(to: dir.appendingPathComponent("SKILL.md"),
                     atomically: true, encoding: .utf8)
        let boot = SuperpowersBootstrap.build(skillsDir: tmp)
        #expect(boot.skillNames == ["mystery"])
        #expect(boot.indexPrompt.contains("- mystery: mystery"))
    }

    @Test func smallFixtureIsSortedAndRendered() {
        // The 2-3 SKILL.md fixture from the dispatch: out-of-order names must
        // render sorted, and the disclosure path stays generic.
        let dir = makeSkillsDir([
            ("zebra", "zebra", "Use when sorting animals"),
            ("apple", "apple", "Use when craving fruit"),
            ("mango", "mango", "Use when in the tropics"),
        ])
        let boot = SuperpowersBootstrap.build(skillsDir: dir)
        #expect(boot.skillNames == ["apple", "mango", "zebra"])
        let lines = boot.indexPrompt.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("- ") }
        #expect(lines == [
            "- apple: Use when craving fruit",
            "- mango: Use when in the tropics",
            "- zebra: Use when sorting animals",
        ])
    }
}
