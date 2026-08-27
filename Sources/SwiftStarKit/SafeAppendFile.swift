import Foundation

/// A file opened for safe appending (item 6, P22 cleanup): every capture
/// producer in this project needs "create the file before appending" —
/// `FileHandle(forWritingAtPath:)` opens an EXISTING file, it does not create
/// one, and a lazy open against a path that was never created silently
/// no-ops every write for the whole session (nothing throws; the writes just
/// vanish). This exact bug shipped once already in this project and cost a
/// whole capture. `SafeAppendFile.init` creates the file (if it doesn't
/// already exist) as part of construction, so a caller cannot get the
/// ordering wrong again — constructing one *is* the guarantee.
///
/// Shared by `AgentController`'s wire/stderr/outcomes tees and
/// `swiftstar-agenttest`'s wire.ndjson capture — the producers that append
/// incrementally as a session runs. `swiftstar-drive`'s `CaptureWriter`
/// buffers its whole session in memory and writes once at the end via
/// `Data.write(to:)`, which has no lazy-open step to get wrong; it does not
/// need this type; see `CaptureWriter`'s own doc.
public final class SafeAppendFile: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle?

    /// Creates `path` as an empty file if it does not already exist, then
    /// opens it for appending. The handle is `nil` only if the open itself
    /// fails after creation (e.g. the containing directory does not exist, or
    /// a permissions problem) — `append` silently no-ops in that case, the
    /// same "capture unavailable" contract every call site already relied on
    /// for a path that never resolved.
    public init(path: String) {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        self.handle = FileHandle(forWritingAtPath: path)
    }

    /// Append `data` to the end of the file. Seeks to the end first — a no-op
    /// when the handle is already there (the common case: one writer, only
    /// ever appending), and necessary when a caller constructs a fresh
    /// `SafeAppendFile` against a path that already has content (e.g. once
    /// per turn, rather than holding a handle open for a whole session).
    ///
    /// Uses `write(contentsOf:)`, not the ObjC-era `write(_:)`: the latter
    /// RAISES on a closed/broken pipe or disk-full/EBADF, which `try?` cannot
    /// catch — it terminates the whole process. `append` swallows the error
    /// instead (matching every capture tee's existing "best-effort" contract:
    /// a capture write failure must never take down the session it is
    /// recording).
    public func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Close the handle. Safe to call more than once, and safe to skip — the
    /// handle also closes on `deinit` — but callers that know a stream has
    /// ended (EOF) close explicitly so the fd is freed promptly rather than
    /// waiting on ARC.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
    }

    deinit {
        try? handle?.close()
    }

    /// Create `path` if it does not already exist, then return a `FileHandle`
    /// opened for writing at it — the same two-step guarantee as `init`, for
    /// a caller that must hand a *raw* `FileHandle` to code that doesn't know
    /// about `SafeAppendFile` (`swiftstar-agenttest`'s capture handle is
    /// threaded through `PoolOrchestrator.runPhase`/`RepairLoop.run`'s public,
    /// widely-used `capture: FileHandle?` parameters, which this cleanup left
    /// alone rather than propagating a type change across every call site).
    ///
    /// Deliberately a plain `FileHandle`, not a `SafeAppendFile` whose handle
    /// you then extract: a `SafeAppendFile` closes its handle on `deinit`, so
    /// exposing the handle while letting the wrapper fall out of scope would
    /// close the very handle the caller is about to hand off to a long-lived
    /// consumer — a footgun this function exists to avoid.
    public static func ensureAndOpen(_ path: String) -> FileHandle? {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        return FileHandle(forWritingAtPath: path)
    }
}
