import Foundation

/// One file's line-ending classification, read from the worktree at dispatch
/// time (D1). `lf` = only LF; `crlf` = only CRLF; `mixed` = both present. A
/// `String`-raw `Codable` so a serialized `FileBaseline` stays human-readable.
public enum LineEnding: String, Codable, Equatable, Sendable, CaseIterable {
    case lf
    case crlf
    case mixed
}

/// One file's baseline at dispatch time (D1): the SHA-256 of its bytes, its
/// line-ending classification, and its Unix mode bits — each read from the
/// worktree, never guessed. The dispatcher revision-checks mutations against
/// `writableFiles`; the baselines let the parent detect drift a candidate
/// introduces on files it was allowed to touch (a changed file differs from
/// its baseline). `Codable` so a `HandoffPacket` round-trips through JSON.
public struct FileBaseline: Codable, Equatable, Sendable {
    public let sha256: String
    public let lineEnding: LineEnding
    public let mode: UInt32

    public init(sha256: String, lineEnding: LineEnding, mode: UInt32) {
        self.sha256 = sha256
        self.lineEnding = lineEnding
        self.mode = mode
    }
}

/// The typed handoff contract (D1): the task text, the exact writable files
/// (relative to the worktree root), the validation command the parent will
/// actually run, a per-file baseline read from the worktree, and the turn and
/// tool-call budgets. The worker gets `read`/`write`/`edit` (no `bash`) under
/// these budgets; every mutation is revision-checked against `writableFiles`.
/// `Codable` so the parent can persist and replay a dispatch.
public struct HandoffPacket: Codable, Equatable, Sendable {
    public let taskText: String
    public let writableFiles: [String]
    public let validationCommand: String?
    public let baselines: [String: FileBaseline]
    public let turnBudget: Int
    public let toolCallBudget: Int

    public init(taskText: String, writableFiles: [String], validationCommand: String?,
                baselines: [String: FileBaseline], turnBudget: Int, toolCallBudget: Int) {
        self.taskText = taskText
        self.writableFiles = writableFiles
        self.validationCommand = validationCommand
        self.baselines = baselines
        self.turnBudget = turnBudget
        self.toolCallBudget = toolCallBudget
    }
}
