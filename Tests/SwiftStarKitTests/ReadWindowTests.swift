import Foundation
import Testing
@testable import SwiftStarKit

struct ReadWindowTests {
    /// n lines, "l1".."ln", with a trailing newline.
    private func sample(_ n: Int) -> String {
        (1...n).map { "l\($0)" }.joined(separator: "\n") + "\n"
    }

    // MARK: - tier defaults (ds4_agent.c:8090, :7885-7889)

    @Test func defaultLinesMatchesTheEngineTiers() {
        #expect(ReadWindow.defaultLines(contextSize: 8192) == 120)
        #expect(ReadWindow.defaultLines(contextSize: 16384) == 240)
        #expect(ReadWindow.defaultLines(contextSize: 32768) == 500)
        #expect(ReadWindow.defaultLines(contextSize: 8193) == 240)
    }

    /// D2: a fixed budget is incoherent at 4k — 7000 bytes is half that
    /// model's entire context in one tool result.
    @Test func byteBudgetScalesWithContextAndIsCappedByTheCondenser() {
        #expect(ReadWindow.byteBudget(contextSize: 4096) == 2048)
        #expect(ReadWindow.byteBudget(contextSize: 8192) == 4096)
        #expect(ReadWindow.byteBudget(contextSize: 32768) == 7000, "capped at the condenser's headroom")
        #expect(ReadWindow.byteBudget(contextSize: 512) == 1024, "floor keeps a pathological setting readable")
    }

    // MARK: - engine parity: degenerate max_lines (ds4_agent.c:8125)

    /// The engine treats `max_lines <= 0` as absent and falls back to the tier
    /// default. Serving 1 line instead — and advertising `count=0` in the
    /// header — is a second contract behind one tool name, which D1 forbids.
    @Test func nonPositiveMaxLinesFallsBackToTheTierDefault() {
        for bad in [0, -5] {
            let r = ReadWindow.render(text: sample(50), path: "a.txt",
                request: .init(startLine: 1, maxLines: bad), defaultLines: 10)
            #expect(r.lastLine == 10, "max_lines=\(bad) must use the tier default, not 1")
            #expect(r.text.hasPrefix(
                "a.txt: lines 1-10 of 50; continue_offset=11; call more with count=10 to read the next chunk\n"),
                "the header must advertise the default, never count=\(bad)")
        }
    }

    // MARK: - engine parity: line terminators (agent_split_lines, :7926-7944)

    /// The engine terminates lines on `\r`, `\n`, or `\r\n`, excluding the
    /// terminator from the content. Splitting on `\n` alone gives a different
    /// line *numbering* — the coordinate system start_line/continue_offset/edit
    /// all share.
    @Test func carriageReturnsTerminateLinesLikeTheEngine() {
        let crlf = ReadWindow.render(text: "alpha\r\nbeta\r\n", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(crlf.totalLines == 2)
        #expect(crlf.text.hasSuffix("1 alpha\n2 beta\n"), "CR must not survive into content")

        let cr = ReadWindow.render(text: "alpha\rbeta\n", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(cr.totalLines == 2, "a lone CR is a line terminator to the engine")
        #expect(cr.text.hasSuffix("1 alpha\n2 beta\n"))

        let mixed = ReadWindow.render(text: "a\r\nb\rc\nd", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(mixed.totalLines == 4)
    }

    // MARK: - window arithmetic

    @Test func servesTheRequestedWindow() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 2, maxLines: 2), defaultLines: 500)
        #expect(r.text.contains("2 l2\n3 l3\n"))
        #expect(!r.text.contains("4 l4"))
        #expect(r.lastLine == 3)
        #expect(r.nextLine == 4)
        #expect(r.totalLines == 5)
    }

    @Test func startLineBelowOneClampsToOne() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 0, maxLines: 1), defaultLines: 500)
        #expect(r.text.contains("1 l1\n"))
    }

    @Test func startLinePastEndYieldsAnEmptyBodyAtEOF() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 99), defaultLines: 500)
        #expect(r.nextLine == nil)
        #expect(!r.text.contains("l1"))
        #expect(r.totalLines == 3)
    }

    @Test func maxLinesPastEndClampsAndReachesEOF() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 1, maxLines: 99), defaultLines: 500)
        #expect(r.lastLine == 3)
        #expect(r.nextLine == nil)
    }

    @Test func wholeReachesEOFWhenItFits() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(whole: true), defaultLines: 1)
        #expect(r.lastLine == 3)
        #expect(r.nextLine == nil)
    }

    // MARK: - header shapes (ds4_agent.c:8148-8154)

    @Test func truncatedHeaderCarriesContinueOffset() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 1, maxLines: 2), defaultLines: 500)
        #expect(r.text.hasPrefix(
            "a.txt: lines 1-2 of 5; continue_offset=3; call more with count=2 to read the next chunk\n"))
    }

    @Test func eofHeaderOmitsContinueOffset() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 1, maxLines: 3), defaultLines: 500)
        #expect(r.text.hasPrefix("a.txt: lines 1-3 of 3\n"))
        #expect(!r.text.contains("continue_offset"))
    }

    @Test func headerCountUsesTheTierDefaultWhenMaxLinesAbsent() {
        let r = ReadWindow.render(text: sample(10), path: "a.txt",
            request: .init(startLine: 1), defaultLines: 4)
        #expect(r.text.hasPrefix(
            "a.txt: lines 1-4 of 10; continue_offset=5; call more with count=4 to read the next chunk\n"))
    }

    @Test func lineBodyUsesTheEngineOneBasedPrefix() {
        let r = ReadWindow.render(text: sample(3), path: "a.txt",
            request: .init(startLine: 1, maxLines: 3), defaultLines: 500)
        #expect(r.text.hasSuffix("1 l1\n2 l2\n3 l3\n"))
    }

    // MARK: - D2: the byte budget wins, and the header never lies

    @Test func byteBudgetCutsBeforeMaxLines() {
        let fat = (1...200).map { "\($0) " + String(repeating: "x", count: 200) }
            .joined(separator: "\n") + "\n"
        let r = ReadWindow.render(text: fat, path: "a.txt",
            request: .init(startLine: 1, maxLines: 200), defaultLines: 500,
            byteBudget: 2000)
        #expect(r.text.utf8.count <= 2000)
        #expect(r.lastLine < 200, "the budget must cut before max_lines")
        #expect(r.nextLine == r.lastLine + 1)
    }

    /// Sibling success for the refusal-adjacent case above (BRIEF rule 4):
    /// when the budget does not bind, the full max_lines is served.
    @Test func budgetDoesNotCutWhenItDoesNotBind() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 1, maxLines: 5), defaultLines: 500,
            byteBudget: 7000)
        #expect(r.lastLine == 5)
        #expect(r.nextLine == nil)
    }

    @Test func headerRangeAlwaysNamesExactlyTheLinesInTheBody() {
        let fat = (1...300).map { "line \($0) " + String(repeating: "y", count: 90) }
            .joined(separator: "\n") + "\n"
        let r = ReadWindow.render(text: fat, path: "a.txt",
            request: .init(startLine: 7, maxLines: 300), defaultLines: 500,
            byteBudget: 3000)
        #expect(r.text.hasPrefix("a.txt: lines 7-\(r.lastLine) of 300;"))
        let body = r.text.split(separator: "\n").dropFirst()
        #expect(body.count == r.lastLine - 6)
        #expect(body.first?.hasPrefix("7 ") == true)
        #expect(body.last?.hasPrefix("\(r.lastLine) ") == true)
    }

    /// The test that would have caught the withdrawn design's error: a rendered
    /// window must survive the responder's condenser untouched (spec rule 4).
    @Test func aRenderedWindowSurvivesTheCondenserUnchanged() {
        let fat = (1...5000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let r = ReadWindow.render(text: fat, path: "a.txt",
            request: .init(startLine: 1), defaultLines: 500)
        #expect(ToolResultCondenser.condense(r.text) == r.text)
    }

    // MARK: - D6: progress is guaranteed

    @Test func aSingleOverBudgetLineIsTruncatedInBandAndAdvances() {
        let huge = String(repeating: "z", count: 9000) + "\nnext\n"
        let r = ReadWindow.render(text: huge, path: "a.txt",
            request: .init(startLine: 1), defaultLines: 500, byteBudget: 2000)
        #expect(r.text.utf8.count <= 2000)
        #expect(r.text.contains("[line 1 truncated at "))
        #expect(r.lastLine == 1)
        #expect(r.nextLine == 2, "continue_offset must advance or `more` loops forever")
    }

    // MARK: - raw mode (ds4_agent.c:8138-8143)

    @Test func rawModeEmitsBytesWithoutPrefixesAndNotesTruncation() {
        let r = ReadWindow.render(text: sample(5), path: "a.txt",
            request: .init(startLine: 1, maxLines: 2, raw: true), defaultLines: 500)
        #expect(r.text.hasPrefix("l1\nl2\n"))
        #expect(!r.text.contains("1 l1"))
        #expect(r.text.contains(
            "[Read truncated at line 2 of 5. continue_offset=3. Call more with count=2 to read the next chunk.]"))
    }

    @Test func rawModeAtEOFHasNoNote() {
        let r = ReadWindow.render(text: sample(2), path: "a.txt",
            request: .init(startLine: 1, maxLines: 2, raw: true), defaultLines: 500)
        #expect(r.text == "l1\nl2\n")
        #expect(r.nextLine == nil)
    }

    // MARK: - edges

    @Test func emptyFileRendersZeroLines() {
        let r = ReadWindow.render(text: "", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(r.totalLines == 0)
        #expect(r.nextLine == nil)
        #expect(r.text.hasPrefix("a.txt: lines 0-0 of 0\n"))
    }

    @Test func fileWithoutTrailingNewlineCountsItsLastLine() {
        let r = ReadWindow.render(text: "a\nb", path: "a.txt",
            request: .init(), defaultLines: 500)
        #expect(r.totalLines == 2)
        #expect(r.text.hasSuffix("1 a\n2 b\n"))
    }
}
