import Foundation

/// A committed capture's provenance: the facts a reader needs to trust and
/// reproduce the capture.
public struct CaptureManifest: Equatable, Sendable {
    public var submoduleSHA: String
    public var commandLine: [String]
    public var model: String
    public var ctx: Int
    public var startedAt: Date

    public init(submoduleSHA: String, commandLine: [String], model: String, ctx: Int, startedAt: Date) {
        self.submoduleSHA = submoduleSHA
        self.commandLine = commandLine
        self.model = model
        self.ctx = ctx
        self.startedAt = startedAt
    }
}

/// Writes the fixed P5 capture format. The wire and stderr files are written
/// byte-for-byte (the verbatim-raw rule); the provenance is rendered. The
/// `--trace` file is written by the engine itself (the driver points `--trace`
/// at `<dir>/wire.trace`), so it is not a parameter here.
public enum CaptureWriter {
    public static func write(
        directory: URL,
        wire: Data,
        stderr: Data,
        manifest: CaptureManifest
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try wire.write(to: directory.appendingPathComponent("wire.ndjson"))
        try stderr.write(to: directory.appendingPathComponent("wire.stderr"))
        try Data(renderProvenance(manifest).utf8).write(to: directory.appendingPathComponent("provenance.md"))
    }

    static func renderProvenance(_ m: CaptureManifest) -> String {
        let iso = ISO8601DateFormatter()
        let date = iso.string(from: m.startedAt)
        let command = m.commandLine.joined(separator: " ")
        return """
        # Capture provenance

        - Submodule (`external/ds4`) SHA: `\(m.submoduleSHA)`
        - Model: `\(m.model)`
        - Context (`-c`): \(m.ctx)
        - Started (wall-clock): \(date)
        - Command line: `\(command)`

        Captured by `swiftstar-drive`. The `wire.ndjson` and `wire.stderr` files are
        byte-for-byte verbatim (the verbatim-raw rule); `wire.trace` is the engine's
        `--trace` output. Timestamps are on the wire (`ts`), and this file records the
        wall-clock start for correlation with the trace's wall-clock stamps.
        """
    }
}
