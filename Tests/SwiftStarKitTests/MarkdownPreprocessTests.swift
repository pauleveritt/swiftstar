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

    @Test func codeIsNotDeLaTeXed() {
        let fenced = "```sh\necho $$\ngrep '\\(a\\)' x \\to y\n```"
        #expect(MarkdownPreprocess.deLaTeXed(fenced) == fenced)
        let tilde = "~~~\n$$ \\pi\n~~~"
        #expect(MarkdownPreprocess.deLaTeXed(tilde) == tilde)
    }

    @Test func inlineCodeIsNotDeLaTeXed() {
        #expect(MarkdownPreprocess.deLaTeXed("run `echo $$` now") == "run `echo $$` now")
    }

    @Test func proseStillDeLaTeXed() {
        #expect(MarkdownPreprocess.deLaTeXed(#"\(x \to y\)"#) == "x → y")
        #expect(MarkdownPreprocess.deLaTeXed("a $$b$$ then\n```\n$$\n```\nand \\pi")
            == "a b then\n```\n$$\n```\nand π")
    }

    @Test func unknownMacrosPassThrough() {
        #expect(MarkdownPreprocess.deLaTeXed(#"\foo{bar}"#) == #"\foo{bar}"#)
    }

    // Final review of 5a1: CommonMark fence and code-span rules.
    @Test func longerFenceHoldsAnInnerFence() {
        let md = "````md\n```sh\necho $$\n```\n````"
        #expect(MarkdownPreprocess.deLaTeXed(md) == md)
    }

    @Test func fenceClosesOnlyOnABareLine() {
        let md = "```\n``` not a close\necho $$\n```"
        #expect(MarkdownPreprocess.deLaTeXed(md) == md)
    }

    @Test func doubleBacktickSpanIsCode() {
        #expect(MarkdownPreprocess.deLaTeXed("run ``echo $$`` now") == "run ``echo $$`` now")
    }

    @Test func loneBacktickDoesNotPairAcrossParagraphs() {
        let md = "Press the ` key, then $$x$$.\n\nRun `echo $$` now."
        #expect(MarkdownPreprocess.deLaTeXed(md) == "Press the ` key, then x.\n\nRun `echo $$` now.")
    }
}
