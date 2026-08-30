/// Adds a bounded hint when a model repeats the same refused tool request.
///
/// The pooled worker and orchestrator loops share this state machine. Keeping
/// it here makes the threshold and reset rules identical without coupling the
/// tracker to either loop's I/O or tool policy.
public struct ToolRefusalTracker: Sendable {
    private var lastSignature: String?
    private var refusedStreak = 0

    public init() {}

    /// Track one response and append a hint on the third consecutive refusal
    /// of the same request. Successful calls reset the streak; a different
    /// refused request starts a new one.
    public mutating func apply(
        _ response: ToolCallbackResponse,
        name: String,
        params: [ToolParam],
        hintSuffix: String = ""
    ) -> ToolCallbackResponse {
        guard !response.ok else {
            lastSignature = nil
            refusedStreak = 0
            return response
        }

        let signature = name + "|"
            + params.map { "\($0.name)=\($0.value)" }.joined(separator: "\u{1e}")
        if signature == lastSignature {
            refusedStreak += 1
        } else {
            lastSignature = signature
            refusedStreak = 1
        }
        guard refusedStreak >= 3 else { return response }

        let hint = "(hint: you have repeated this identical request \(refusedStreak) times and it was refused each time; it will not be allowed.\(hintSuffix))"
        return ToolCallbackResponse(
            idx: response.idx, ok: false, s: response.s + " " + hint,
            mutations: response.mutations, exitStatus: response.exitStatus,
            outputDigest: response.outputDigest, validationRan: response.validationRan)
    }
}
