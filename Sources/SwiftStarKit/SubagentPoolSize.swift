/// The `--subagent-pool` value's guardrail (P19.1 D3): one orchestrator plus
/// N-1 workers, bounded so a hand-edited preference cannot request a nonsense
/// pool. Pure.
public enum SubagentPoolSize {
    public static let min = 1
    public static let max = 8
    public static func clamp(_ raw: Int) -> Int { Swift.min(Swift.max(raw, min), max) }
}
