import Foundation

/// Decodes the tool names a `--trace`d engine spawn actually advertised, from
/// the trace's `initial_system_prompt` token dump (`agent_trace_tokens`/
/// `agent_trace_token` in `ds4_agent.c`). Moved out of
/// `ToolsFilterIntegrationTests` (eval-cli task 1, which pinned this against
/// the real engine) so `swiftstar-eval experiment` can run the identical
/// decode against a run's own `agent.trace` — decision 6 of task 7: a record
/// that merely repeats the tool set the caller *asked* for, without checking
/// what the engine actually *advertised*, is the defect this project keeps
/// rediscovering (BRIEF.md, the 2026-08-30 incident).
///
/// Pure: no process spawn, no socket — the caller reads `agent.trace` off
/// disk and hands the text in, per `SwiftStarKit`'s fast-tier contract.
public enum AdvertisedToolNames {
    /// Decode every token's `text="..."` payload from the trace's
    /// `initial_system_prompt` dump, concatenate the decoded text, and
    /// extract the `"name"` key's string value from every schema object —
    /// the Swift mirror of the engine test suite's own
    /// `agent_test_tool_names` helper (`ds4_agent.c`), so both sides agree on
    /// what "the advertised tool names" means. Tolerates both schema
    /// spellings: compact (`"name":"x"`) and DSML's pretty-printed
    /// (`"name": "x"`).
    public static func names(fromTrace trace: String) -> Set<String> {
        var decoded = ""
        var scan = trace.startIndex
        let needle = "text=\""
        while let range = trace.range(of: needle, range: scan..<trace.endIndex) {
            var i = range.upperBound
            var token = ""
            while i < trace.endIndex, trace[i] != "\"" {
                if trace[i] == "\\", trace.index(after: i) < trace.endIndex {
                    let next = trace[trace.index(after: i)]
                    switch next {
                    case "n": token.append("\n")
                    case "r": token.append("\r")
                    case "t": token.append("\t")
                    case "\"": token.append("\"")
                    case "\\": token.append("\\")
                    default: token.append(next)
                    }
                    i = trace.index(i, offsetBy: 2)
                } else {
                    token.append(trace[i])
                    i = trace.index(after: i)
                }
            }
            decoded += token
            scan = i < trace.endIndex ? trace.index(after: i) : trace.endIndex
        }

        var names: Set<String> = []
        var i = decoded.startIndex
        let key = "\"name\""
        while let range = decoded.range(of: key, range: i..<decoded.endIndex) {
            var j = range.upperBound
            while j < decoded.endIndex, decoded[j] == " " { j = decoded.index(after: j) }
            guard j < decoded.endIndex, decoded[j] == ":" else { i = range.upperBound; continue }
            j = decoded.index(after: j)
            while j < decoded.endIndex, decoded[j] == " " { j = decoded.index(after: j) }
            guard j < decoded.endIndex, decoded[j] == "\"" else { i = range.upperBound; continue }
            let start = decoded.index(after: j)
            var k = start
            while k < decoded.endIndex, decoded[k] != "\"" { k = decoded.index(after: k) }
            names.insert(String(decoded[start..<k]))
            i = k < decoded.endIndex ? decoded.index(after: k) : decoded.endIndex
        }
        return names
    }
}
