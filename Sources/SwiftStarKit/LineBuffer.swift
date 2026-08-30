import Foundation

/// Incremental newline framing for the agent's line-oriented wires.
///
/// A read from a pipe is allowed to end in the middle of a line or contain
/// several lines. Callers retain this value across reads; completed lines are
/// returned in order and incomplete bytes stay buffered for the next append.
public struct LineBuffer: Sendable {
    private var data = Data()

    public init() {}

    /// Append a byte chunk and return every complete line it contains.
    /// The newline is consumed but not included in the returned byte strings.
    /// Keeping bytes here lets capture producers preserve invalid UTF-8 exactly
    /// while parsers can decode each line lossily at their boundary.
    public mutating func append(_ chunk: Data) -> [Data] {
        data.append(chunk)
        var lines: [Data] = []
        while let newline = data.firstIndex(of: 0x0A) {
            let line = Data(data[..<newline])
            data.removeSubrange(data.startIndex...newline)
            lines.append(line)
        }
        return lines
    }

    /// Drop a final unterminated line, if any. Agent wires require newline
    /// terminated records, so this is diagnostic-only rather than a normal
    /// parsing path.
    public mutating func finish() -> Data? {
        guard !data.isEmpty else { return nil }
        defer { data.removeAll(keepingCapacity: false) }
        return data
    }
}
