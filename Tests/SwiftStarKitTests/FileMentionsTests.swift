import Testing
@testable import SwiftStarKit

// SU.14: the `@` picker's rules, ported from ds4-engine's relevance.py.
struct FileMentionsTests {
    @Test(arguments: [
        ("see @Ses", "Ses"), ("@", ""), ("line one\n@Pa", "Pa"),
        ("a@b", nil), ("@x ", nil), ("hello", nil), ("", nil),
    ] as [(String, String?)])
    func activeQuery(_ text: String, _ query: String?) {
        #expect(FileMentions.activeQuery(in: text) == query)
    }

    @Test func insertReplacesTheWordBeingTyped() {
        #expect(FileMentions.insert("Sources/A.swift", into: "see @Ses") == "see @Sources/A.swift ")
        #expect(FileMentions.insert("Sources/A.swift", into: "@") == "@Sources/A.swift ")
    }

    @Test func fuzzyTiers() {
        let path = "Sources/SwiftStarUI/Session/SessionView.swift"
        #expect(FileMentions.fuzzy("sess", path)?.tier == 3)   // the name starts with it
        #expect(FileMentions.fuzzy("view", path)?.tier == 2)   // the name holds it
        #expect(FileMentions.fuzzy("ui/se", path)?.tier == 1)  // the path holds it
        #expect(FileMentions.fuzzy("ssvw", path)?.tier == 0)   // a subsequence
        #expect(FileMentions.fuzzy("zzz", path) == nil)
        #expect(FileMentions.fuzzy("", path)?.tier == 0)
        // The engine's scores for the same calls, to two places.
        func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.005 } ?? false }
        #expect(near(FileMentions.fuzzy("sess", path)?.score, -0.45))
        #expect(near(FileMentions.fuzzy("ssvw", path)?.score, 0.05))
        #expect(near(FileMentions.fuzzy("ses", "Sources/Composer.swift")?.score, 0.4467))
    }

    @Test func matchOrdersByTierThenScore() {
        let paths = ["README.md", "Sources/SessionView.swift", "Sources/SessionToolbar.swift",
                     "docs/session.md", "Sources/Composer.swift"]
        // As ds4-engine's own fuzzy_match ranks them (run on these paths,
        // 2026-10-14): three names start with "ses", shortest first; then
        // Composer.swift, a subsequence (s…e…s).
        #expect(FileMentions.match("ses", in: paths)
            == ["docs/session.md", "Sources/SessionView.swift", "Sources/SessionToolbar.swift",
                "Sources/Composer.swift"])
        #expect(FileMentions.match("ses", in: paths, limit: 1) == ["docs/session.md"])
        #expect(FileMentions.match("", in: paths, limit: 2).count == 2)
    }

    @Test func wantedFiles() {
        #expect(FileMentions.wanted("Sources/A.swift", size: 120))
        #expect(!FileMentions.wanted("icon.png", size: 120))
        #expect(!FileMentions.wanted("a b.swift", size: 120))
        #expect(!FileMentions.wanted("x@y.swift", size: 120))
        #expect(!FileMentions.wanted("big.json", size: 3 * 1024 * 1024))
        #expect(!FileMentions.wanted("gone.swift", size: nil))
        #expect(FileMentions.wanted("empty.txt", size: 0))
        #expect(!FileMentions.wanted("Makefile", size: 0))
    }

    @Test func skippedDirectories() {
        #expect(FileMentions.skipped(directory: ".git"))
        #expect(FileMentions.skipped(directory: "node_modules"))
        #expect(FileMentions.skipped(directory: "Foo.egg-info"))
        #expect(!FileMentions.skipped(directory: "Sources"))
        #expect(FileMentions.inSkippedDirectory("build/x/a.swift"))
        #expect(!FileMentions.inSkippedDirectory("Sources/a.swift"))
    }

    @Test func mentionsBecomeARowAndKeepThePromptPending() {
        var t = EngineTranscript()
        t.appendUser("look at @a.py")
        t.apply(.mentions(attached: ["a.py"], missing: ["b.py: no such file"]))
        #expect(t.rows.last == .mentions(attached: ["a.py"], missing: ["b.py: no such file"]))
        #expect(t.isPending(rowAt: 0))
    }
}
