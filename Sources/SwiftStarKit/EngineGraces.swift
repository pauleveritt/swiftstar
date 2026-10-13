import Foundation


/// How long a quit waits at each step before escalating: after `stop`, after
/// SIGTERM, after SIGKILL. `safetyBound` is when the app stops waiting
/// altogether, so app quit can never hang.
public struct EngineGraces: Equatable, Sendable {
    public var stop: Duration
    public var term: Duration
    public var kill: Duration
    public var safetyBound: Duration

    public init(stop: Duration, term: Duration, kill: Duration, safetyBound: Duration? = nil) {
        self.stop = stop
        self.term = term
        self.kill = kill
        self.safetyBound = safetyBound ?? stop + term + kill + .seconds(5)
    }

    public static let standard = EngineGraces(stop: .seconds(10), term: .seconds(5), kill: .seconds(10))
}

/// Facts about the engine's process output that more than one place needs.
public enum EngineSessionConstants {
    /// How much of stderr's end is kept for an exit message.
    public static let stderrTailLimit = 4096
    /// The stderr line that names the session directory.
    public static let sessionArtifactsMarker = "Session artifacts:"
}

extension String {
    /// The string with surrounding whitespace and newlines removed, or nil
    /// when nothing is left.
    public var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
