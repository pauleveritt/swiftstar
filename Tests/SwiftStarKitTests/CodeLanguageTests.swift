import Testing
@testable import SwiftStarKit

// SU.15, D3: a tool card's language, from its path, in highlight.js's names.
struct CodeLanguageTests {
    @Test(arguments: [
        ("app.py", "python"), ("Sources/A.swift", "swift"), ("specs/roadmap.md", "markdown"),
        ("pyproject.toml", "ini"), ("Makefile", "makefile"), ("README.MD", "markdown"),
        ("notes.txt", nil), ("LICENSE", nil), ("", nil),
    ] as [(String, String?)])
    func forPath(_ path: String, _ language: String?) {
        #expect(CodeLanguage.forPath(path) == language)
    }
}
