import Foundation
import Testing
@testable import SwiftStarKit

struct MarkdownPreprocessTests {
    // MARK: deLaTeXed

    @Test func stripsLatexWrappers() {
        #expect(MarkdownPreprocess.deLaTeXed(#"\[x^2\]"#) == "x^2")
        #expect(MarkdownPreprocess.deLaTeXed(#"\(a\)"#) == "a")
        #expect(MarkdownPreprocess.deLaTeXed("$$b$$") == "b")
    }

    @Test func mapsCommonMacros() {
        #expect(MarkdownPreprocess.deLaTeXed(#"\boxed{42}"#) == "**42**")
        #expect(MarkdownPreprocess.deLaTeXed(#"\text{hi}"#) == "hi")
        #expect(MarkdownPreprocess.deLaTeXed(#"\frac{1}{2}"#) == "1/2")
        #expect(MarkdownPreprocess.deLaTeXed(#"a \times b"#) == "a × b")
        #expect(MarkdownPreprocess.deLaTeXed(#"\rightarrow"#) == "→")
    }

    @Test func unknownMacrosPassThrough() {
        #expect(MarkdownPreprocess.deLaTeXed(#"\foo{bar}"#) == #"\foo{bar}"#)
    }

    // MARK: stripTaggedBlocks

    @Test func stripsMultilineTaggedBlock() {
        let input = "before\n<thinking>\nsecret reasoning\n</thinking>\nafter"
        #expect(MarkdownPreprocess.stripTaggedBlocks(input) == "before\nafter")
    }

    @Test func stripsInlineTaggedLine() {
        let input = "text\n<tool_call>pkg(foo)</tool_call>\nmore"
        #expect(MarkdownPreprocess.stripTaggedBlocks(input) == "text\nmore")
    }

    @Test func leavesProseWithAngleBracketsAlone() {
        #expect(MarkdownPreprocess.stripTaggedBlocks("a < b and c > d") == "a < b and c > d")
    }

    @Test func unterminatedBlockStaysHidden() {
        #expect(MarkdownPreprocess.stripTaggedBlocks("<thinking>\nopen") == "")
    }

    // MARK: fenced / language

    @Test func fencedUsesMinimalFence() {
        #expect(MarkdownPreprocess.fenced("let x = 1", language: "swift")
            == "```swift\nlet x = 1\n```")
    }

    @Test func fencedOutgrowsInnerBacktickRuns() {
        // A body containing ``` must not break out of a fixed 3-backtick fence.
        let body = "a\n```\nb"
        #expect(MarkdownPreprocess.fenced(body, language: "")
            == "````\na\n```\nb\n````")
    }

    @Test func languageFromPathExtension() {
        #expect(MarkdownPreprocess.language(forPath: "hello.c") == "c")
        #expect(MarkdownPreprocess.language(forPath: "dir/a.b.swift") == "swift")
        #expect(MarkdownPreprocess.language(forPath: "noext") == "")
        #expect(MarkdownPreprocess.language(forPath: nil) == "")
    }
}
