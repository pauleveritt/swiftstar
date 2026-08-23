import Foundation

/// The DeepSeek grader's structured verdict (P11 addendum D6): a "good"/"bad"
/// read with reasons, or `.error` when the call failed or the response did not
/// parse — the grader never fabricates a pass, so an unreadable verdict is
/// recorded as an error, not as "good".
public struct GraderVerdict: Equatable, Sendable {
    public enum Verdict: String, Equatable, Sendable {
        case good
        case bad
        case error
    }

    public let verdict: Verdict
    public let reasons: [String]

    public init(verdict: Verdict, reasons: [String]) {
        self.verdict = verdict
        self.reasons = reasons
    }

    /// Parse the grader's response: `{"verdict":"good"|"bad","reasons":[…]}`.
    /// Any shape that does not carry a recognised `verdict` string yields
    /// `.error` (fail closed — never interpret garbage as a pass).
    public static func parse(_ json: String) -> GraderVerdict {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["verdict"] as? String,
              let verdict = Verdict(rawValue: raw) else {
            return GraderVerdict(verdict: .error, reasons: [])
        }
        let reasons = (obj["reasons"] as? [String]) ?? []
        return GraderVerdict(verdict: verdict, reasons: reasons)
    }
}
