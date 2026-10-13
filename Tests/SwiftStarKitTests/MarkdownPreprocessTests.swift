import Foundation
import Testing
@testable import SwiftStarKit

struct MarkdownPreprocessTests {
    struct ProseCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let output: String
    }

    static let proseCases: [ProseCase] = [
        .init(testDescription: "stripsLatexWrappers (display)", input: #"\[x^2\]"#, output: "x^2"),
        .init(testDescription: "stripsLatexWrappers (inline)", input: #"\(a\)"#, output: "a"),
        .init(testDescription: "stripsLatexWrappers (dollars)", input: "$$b$$", output: "b"),
        .init(testDescription: "mapsCommonMacros (boxed)", input: #"\boxed{42}"#, output: "**42**"),
        .init(testDescription: "mapsCommonMacros (text)", input: #"\text{hi}"#, output: "hi"),
        .init(testDescription: "mapsCommonMacros (frac)", input: #"\frac{1}{2}"#, output: "1/2"),
        .init(testDescription: "mapsCommonMacros (times)", input: #"a \times b"#, output: "a × b"),
        .init(testDescription: "mapsCommonMacros (arrow)", input: #"\rightarrow"#, output: "→"),
        .init(testDescription: "proseStillDeLaTeXed", input: #"\(x \to y\)"#, output: "x → y"),
        .init(testDescription: "proseStillDeLaTeXed (around a fence)",
              input: "a $$b$$ then\n```\n$$\n```\nand \\pi", output: "a b then\n```\n$$\n```\nand π"),
        .init(testDescription: "unknownMacrosPassThrough", input: #"\foo{bar}"#, output: #"\foo{bar}"#),
        .init(testDescription: "loneBacktickDoesNotPairAcrossParagraphs",
              input: "Press the ` key, then $$x$$.\n\nRun `echo $$` now.",
              output: "Press the ` key, then x.\n\nRun `echo $$` now."),
    ]

    @Test(arguments: proseCases) func prose(_ c: ProseCase) {
        #expect(MarkdownPreprocess.deLaTeXed(c.input) == c.output)
    }

    // Final review of 5a1: CommonMark fence and code-span rules.
    @Test(arguments: [
        "```sh\necho $$\ngrep '\\(a\\)' x \\to y\n```",   // codeIsNotDeLaTeXed
        "~~~\n$$ \\pi\n~~~",                               // codeIsNotDeLaTeXed (tilde)
        "run `echo $$` now",                               // inlineCodeIsNotDeLaTeXed
        "````md\n```sh\necho $$\n```\n````",               // longerFenceHoldsAnInnerFence
        "````\n```\n$$x$$\n````",                          // longerFenceHoldsAnInnerFence (bare inner fence)
        "```\n``` not a close\necho $$\n```",              // fenceClosesOnlyOnABareLine
        "run ``echo $$`` now",                             // doubleBacktickSpanIsCode
    ]) func codeIsVerbatim(_ md: String) {
        #expect(MarkdownPreprocess.deLaTeXed(md) == md)
    }
}
