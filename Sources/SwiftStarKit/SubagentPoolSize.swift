/// The `--subagent-pool` value's guardrail (P19.1 D3): one orchestrator plus
/// N-1 workers, bounded so a hand-edited preference cannot request a nonsense
/// pool. Pure.
public enum SubagentPoolSize {
    /// Pool 1 is orchestrator-only: the engine turns worker prompts into bare
    /// orchestrator text (ds4_agent.c: pool-prompt parsing is off when N==1),
    /// so a delegation pool with no workers corrupts the main session. Minimum
    /// is 2.
    public static let min = 2
    public static let max = 8
    public static func clamp(_ raw: Int) -> Int { Swift.min(Swift.max(raw, min), max) }
    /// Worker sessions = pool − 1 (one orchestrator + N−1 workers), never below
    /// one — the scheduler must not hand out a worker id the engine doesn't host.
    public static func workerCapacity(_ pool: Int) -> Int { Swift.max(clamp(pool) - 1, 1) }
}
