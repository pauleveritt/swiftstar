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
        // SU.6a final review: a fence indented under a list item is still a
        // fence, so its code stays as written and the prose after converts.
        .init(testDescription: "listItemFenceKeepsItsCode",
              input: "1. Run:\n\n    ```\necho $$\n    ```\n\nThen $$x$$.",
              output: "1. Run:\n\n    ```\necho $$\n    ```\n\nThen x."),
        // A lazy continuation (indented, straight after paragraph text) is prose.
        .init(testDescription: "indentedLazyContinuationIsProse", input: "Text\n    \\(x\\)", output: "Text\n    x"),
        // SU.17: markers alone open nothing; the prose after a closed fence converts.
        .init(testDescription: "quotedProseStillDeLaTeXed", input: "> $$x$$ and - \\pi", output: "> x and - π"),
        .init(testDescription: "proseAfterAListFenceConverts",
              input: "- ```\n  $$\n  ```\n\nThen $$x$$.", output: "- ```\n  $$\n  ```\n\nThen x."),
        .init(testDescription: "emphasisIsNotAListMarker", input: "*a* $$b$$", output: "*a* b"),
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
        "Intro.\n\n    echo $$\n    \\to y",               // indentedCodeAfterBlankLine (SU.6a)
        "\techo \\to y",                                  // tabIndentedCodeAtStart
        "- item\n\n    \\(a\\) stays",                     // indentedListParagraphKeptRaw (accepted trade-off)
        // An indented fence marker opens a fence; unclosed, the rest stays as
        // written (D4: when unsure, leave it). Replaced indentedFenceMarkerOpensNoFence.
        "Intro.\n\n    ```\n\nThen $$x$$.",                 // indentedFenceMarkerOpensAFence
        // SU.17, finding 7: a fence opened on a list or quote line.
        "- ```sh\n  echo $$\n  ```",                        // fenceOnABulletLine
        "1. ```\n   x \\times y\n   ```",                    // fenceOnANumberedLine
        "> ```\n> grep '\\(a\\)'\n> ```",                   // fenceInAQuote
        "> - ```\n>   echo $$\n>   ```",                     // fenceInAQuotedList
        ">     echo $$",                                    // indentedCodeInAQuote
        "> Intro.\n>\n>     echo $$",                      // indentedCodeInAQuote (after a quoted blank)
    ]) func codeIsVerbatim(_ md: String) {
        #expect(MarkdownPreprocess.deLaTeXed(md) == md)
    }
}
