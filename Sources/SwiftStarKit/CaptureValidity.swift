import Foundation

public enum CaptureValidity {
    public enum Status: String, Codable, Equatable, Sendable {
        case pass
        case fail
        case unauditable
    }

    public struct Check: Codable, Equatable, Sendable {
        public let status: Status
        public let detail: String?

        public init(status: Status, detail: String? = nil) {
            self.status = status
            self.detail = detail
        }
    }

    public struct Result: Codable, Equatable, Sendable {
        public let v5: Check
        public let v6: Check

        public init(v5: Check, v6: Check) {
            self.v5 = v5
            self.v6 = v6
        }
    }

    private static let writableFiles: Set<String> = [
        "app.py", "models.py", "templates/base.html",
        "templates/home.html", "templates/complaints.html",
        "tests/test_app.py"
    ]

    public static func audit(wire: String?) -> Result {
        guard let wire else {
            let check = Check(status: .unauditable, detail: "no wire.ndjson")
            return Result(v5: check, v6: check)
        }
        return Result(v5: checkV5(wire), v6: checkV6(wire))
    }

    public static func checkV5(_ wire: String) -> Check {
        if wire.contains("exceeds context") {
            return Check(status: .fail, detail: "exceeds context")
        }
        if wire.contains("turnDidNotEnd") {
            return Check(status: .fail, detail: "turnDidNotEnd")
        }
        let pattern = "\"stop_reason\"\\s*:\\s*\"(\\w+)\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for rawLine in wire.split(whereSeparator: \.isNewline) {
                let line = String(rawLine)
                let range = NSRange(location: 0, length: line.utf16.count)
                guard let match = regex.firstMatch(in: line, range: range),
                      let valueRange = Range(match.range(at: 1), in: line)
                else { continue }
                let reason = String(line[valueRange])
                if reason == "limit" || reason == "contextFull" {
                    return Check(status: .fail, detail: "stop_reason=\(reason)")
                }
            }
        }
        return Check(status: .pass)
    }

    public static func checkV6(_ wire: String) -> Check {
        let discarded = discardedFences(in: turns(in: wire))
        guard !discarded.isEmpty else { return Check(status: .pass) }
        let paths = Set(discarded).sorted()
            .map { "'\($0)'" }
            .joined(separator: ", ")
        return Check(
            status: .fail,
            detail: "\(discarded.count) heading(s) had fenced code discarded in favour of commentary: [\(paths)]")
    }

    private static func turns(in wire: String) -> [String] {
        var turns: [String] = []
        var current: [String] = []
        for rawLine in wire.split(whereSeparator: \.isNewline) {
            guard let data = String(rawLine).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            switch object["t"] as? String {
            case "text":
                current.append(object["s"] as? String ?? "")
            case "ready":
                turns.append(current.joined())
                current.removeAll()
            default:
                break
            }
        }
        if !current.isEmpty { turns.append(current.joined()) }
        return turns
    }

    private static func discardedFences(in turns: [String]) -> [String] {
        var discarded: [String] = []
        for turn in turns {
            let lines = turn.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for i in lines.indices {
                guard let heading = headingPath(lines[i]),
                      writableFiles.contains(heading)
                else { continue }

                var j = i + 1
                if j < lines.count,
                   lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1
                }
                if j < lines.count, isFence(lines[j]) { continue }

                var k = j
                while k < lines.count {
                    if isFence(lines[k]) {
                        discarded.append(heading)
                        break
                    }
                    if let next = headingPath(lines[k]),
                       writableFiles.contains(next) {
                        break
                    }
                    k += 1
                }
            }
        }
        return discarded
    }

    private static func headingPath(_ line: String) -> String? {
        var rest = line.trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("#") else { return nil }
        while rest.hasPrefix("#") { rest.removeFirst() }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        if rest.hasPrefix("`") && rest.hasSuffix("`") && rest.count >= 2 {
            return String(rest.dropFirst().dropLast())
        }
        return rest
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }
}
