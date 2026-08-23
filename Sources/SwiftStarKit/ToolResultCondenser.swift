import Foundation

/// Deterministic size cap for tool results before they enter KV (D3, P9): a
/// result under `limit` passes through unchanged; one over `limit` is replaced
/// by a head + tail summary joined by a one-line
/// `"\n[truncated: N of M bytes shown]\n"` marker, where M is the original
/// UTF-8 byte count and N is the bytes retained (head + tail). Cuts land on
/// UTF-8 codepoint boundaries so the output is always valid UTF-8, and the
/// output never exceeds `limit` bytes. Pure and deterministic — the same input
/// always yields the same output, with no randomness and no I/O. This is the
/// "condenses tool results before they enter KV" piece: a 4 MB read becomes a
/// bounded head/tail summary rather than 4 MB of KV text.
public enum ToolResultCondenser {
    /// Condense `text` to at most `limit` UTF-8 bytes. Under `limit` the text
    /// is returned unchanged; over `limit` it becomes
    /// `head + "\n[truncated: N of M bytes shown]\n" + tail` where M is the
    /// original byte count and N the bytes shown (head + tail). The default
    /// cap is 8000.
    public static func condense(_ text: String, limit: Int = 8000) -> String {
        let bytes = Array(text.utf8)
        let total = bytes.count
        guard total > limit else { return text }

        // Upper bound on the marker's UTF-8 length so the output stays ≤ limit:
        // the real marker uses `shown ≤ total`, so its digit runs are no longer
        // than the `total`-valued version below.
        let markerMaxLen = "\n[truncated: \(total) of \(total) bytes shown]\n".utf8.count
        let keep = max(0, limit - markerMaxLen)
        let headBudget = keep / 2
        let tailBudget = keep - headBudget

        let headEnd = utf8PrefixCut(bytes, budget: headBudget)
        let tailStart = utf8SuffixCut(bytes, budget: tailBudget)
        let head = String(decoding: bytes[0..<headEnd], as: UTF8.self)
        let tail = String(decoding: bytes[tailStart..<total], as: UTF8.self)
        let shown = headEnd + (total - tailStart)
        let marker = "\n[truncated: \(shown) of \(total) bytes shown]\n"
        return head + marker + tail
    }

    /// The largest byte offset ≤ `budget` at which `bytes` can be split without
    /// splitting a UTF-8 codepoint — i.e. `bytes[0..<offset]` is valid UTF-8.
    /// A continuation byte is `0b10xxxxxx` (`0x80..<0xC0`); walking back past
    /// one lands on the codepoint start, leaving the slice valid.
    private static func utf8PrefixCut(_ bytes: [UInt8], budget: Int) -> Int {
        var end = min(budget, bytes.count)
        while end > 0 && end < bytes.count && bytes[end] >= 0x80 && bytes[end] < 0xC0 {
            end -= 1
        }
        return end
    }

    /// The smallest byte offset ≥ `count - budget` at which `bytes` can be
    /// split without splitting a UTF-8 codepoint — i.e.
    /// `bytes[offset..<count]` is valid UTF-8.
    private static func utf8SuffixCut(_ bytes: [UInt8], budget: Int) -> Int {
        var start = max(0, bytes.count - budget)
        while start < bytes.count && bytes[start] >= 0x80 && bytes[start] < 0xC0 {
            start += 1
        }
        return start
    }
}
