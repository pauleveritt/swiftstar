import Foundation

/// Deterministic, host-owned derivation of the project's test and lint
/// commands from the workspace — the model never names a command (P24.3
/// evidence 1). Swift wins in mixed repos: a `Package.swift` is the app;
/// `pyproject.toml` may be tooling.
public enum ProjectCommandResolver {
    public enum ProjectKind: Equatable, Sendable {
        case swift
        case python
    }

    /// Pure core over the set of marker files present — fast-tier testable
    /// without filesystem I/O.
    public static func kind(having markers: Set<String>) -> ProjectKind? {
        if markers.contains("Package.swift") { return .swift }
        if markers.contains("pyproject.toml") { return .python }
        return nil
    }

    public static func kind(in workspace: URL) -> ProjectKind? {
        let fm = FileManager.default
        let present = ["Package.swift", "pyproject.toml"]
            .filter { fm.fileExists(atPath: workspace.appendingPathComponent($0).path) }
        return kind(having: Set(present))
    }

    public static func testCommand(in workspace: URL) -> String? {
        switch kind(in: workspace) {
        case .swift: return "swift test"
        case .python: return "uv run pytest"
        case nil: return nil
        }
    }

    /// `lint` targets Python (ruff) per the P24 row. A workspace with no ruff
    /// target resolves nil and the tool refuses deterministically.
    public static func lintCommand(in workspace: URL) -> String? {
        let fm = FileManager.default
        let hasRuffTarget = ["pyproject.toml", ".ruff.toml", "ruff.toml"]
            .contains { fm.fileExists(atPath: workspace.appendingPathComponent($0).path) }
        guard hasRuffTarget else { return nil }
        return "uv run ruff check --output-format=json"
    }

    /// The `test` selector is a typed filter, never a command: only the
    /// charset `[A-Za-z0-9_./:-]` is admitted (`:` is pytest's `::` node-id
    /// separator and is shell-safe); anything else is refused, not executed.
    public static func isValidSelector(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy {
            $0.isASCII && "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-".contains($0)
        }
    }
}
