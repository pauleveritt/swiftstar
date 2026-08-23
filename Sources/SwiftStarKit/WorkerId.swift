import Foundation

/// A worker's identity on the pooled wire (D1): one engine hosts N sessions,
/// each event line carries a `worker` id. `0` is the orchestrator (the project
/// session). Absent on a single-session wire, so a parser defaults to `.orchestrator`.
public struct WorkerId: RawRepresentable, Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public static let orchestrator = WorkerId(rawValue: 0)
    public static func < (lhs: WorkerId, rhs: WorkerId) -> Bool { lhs.rawValue < rhs.rawValue }
}
