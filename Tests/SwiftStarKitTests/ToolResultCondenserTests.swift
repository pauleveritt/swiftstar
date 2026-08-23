import Testing
import Foundation
@testable import SwiftStarKit

// P9 D3: ToolResultCondenser is the pure, deterministic size cap that keeps a
// 4 MB tool result out of KV. Under `limit` the text passes through; over
// `limit` it becomes head + a one-line `[truncated: N of M bytes shown]`
// marker + tail, cut on UTF-8 boundaries so the output is always valid UTF-8.
struct ToolResultCondenserTests {
    @Test func underLimitReturnedUnchanged() {
        #expect(ToolResultCondenser.condense("hello, world", limit: 100) == "hello, world")
        // Exactly at the limit is unchanged (the cap is strict >).
        let exact = String(repeating: "x", count: 50)
        #expect(ToolResultCondenser.condense(exact, limit: 50) == exact)
    }

    @Test func emptyAndShortStringsUnchanged() {
        #expect(ToolResultCondenser.condense("", limit: 10) == "")
        #expect(ToolResultCondenser.condense("a", limit: 10) == "a")
        #expect(ToolResultCondenser.condense("ab", limit: 10) == "ab")
    }

    @Test func overLimitCondensesAndStaysUnderLimit() {
        let text = String(repeating: "x", count: 1000)
        let out = ToolResultCondenser.condense(text, limit: 100)
        #expect(out != text)
        #expect(out.utf8.count <= 100)
        #expect(out.contains("[truncated:"))
        #expect(out.contains(" bytes shown]"))
        // M is the total byte count; the marker reports it.
        #expect(out.contains(" of 1000 bytes shown]"))
    }

    @Test func exactOutputPinnedForAscii() {
        // 200 bytes over limit 100: markerMaxLen = 37 (for "200 of 200"),
        // keep = 63, head = 31, tail = 32, shown = 63; the marker
        // "\n[truncated: 63 of 200 bytes shown]\n" is 36 bytes; the whole
        // output is 31 + 36 + 32 = 99 bytes (<= 100).
        let text = String(repeating: "a", count: 200)
        let out = ToolResultCondenser.condense(text, limit: 100)
        let expected = String(repeating: "a", count: 31)
            + "\n[truncated: 63 of 200 bytes shown]\n"
            + String(repeating: "a", count: 32)
        #expect(out == expected)
    }

    @Test func multibyteUtf8CutsOnBoundaries() {
        // '🌍' is 4 UTF-8 bytes; a naive byte cut would split a codepoint. The
        // condenser cuts on codepoint boundaries, so the head and tail are each
        // whole codepoints and the output round-trips as valid UTF-8.
        let text = String(repeating: "🌍", count: 60)  // 240 bytes
        let out = ToolResultCondenser.condense(text, limit: 100)
        #expect(out.utf8.count <= 100)
        #expect(out.contains("[truncated:"))
        #expect(String(data: Data(out.utf8), encoding: .utf8) == out)
        // The retained head is a prefix of the original; the tail a suffix.
        let head = String(out[..<out.range(of: "\n[truncated:")!.lowerBound])
        let tail = String(out[out.range(of: " bytes shown]\n")!.upperBound...])
        #expect(text.hasPrefix(head))
        #expect(text.hasSuffix(tail))
        // Every retained slice is a whole number of 4-byte codepoints.
        #expect(head.utf8.count % 4 == 0)
        #expect(tail.utf8.count % 4 == 0)
        #expect(!head.isEmpty)
        #expect(!tail.isEmpty)
    }

    @Test func defaultLimitIs8000() {
        // The default cap is 8000; at-or-under passes through, over condenses.
        let under = String(repeating: "x", count: 8000)
        #expect(ToolResultCondenser.condense(under) == under)
        let over = String(repeating: "x", count: 8001)
        let out = ToolResultCondenser.condense(over)
        #expect(out != over)
        #expect(out.utf8.count <= 8000)
        #expect(out.contains("[truncated:"))
        #expect(out.contains(" of 8001 bytes shown]"))
    }

    @Test func condenseIsDeterministic() {
        let text = String(repeating: "z", count: 5000)
        let a = ToolResultCondenser.condense(text, limit: 200)
        let b = ToolResultCondenser.condense(text, limit: 200)
        #expect(a == b)
    }
}
