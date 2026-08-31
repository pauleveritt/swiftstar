import Foundation

/// Deterministic, host-owned command selection for a workspace. The model may
/// select a test target, but never supplies the command itself.
public enum ProjectCommandResolver {
    public enum ProjectKind: Equatable, Sendable {
        case swift
        case python
    }

    public static func kind(having markers: Set<String>) -> ProjectKind? {
        if markers.contains("Package.swift") { return .swift }
        if markers.contains("pyproject.toml") { return .python }
        return nil
    }

    public static func kind(in workspace: URL) -> ProjectKind? {
        let markers = ["Package.swift", "pyproject.toml"].filter {
            FileManager.default.fileExists(atPath: workspace.appendingPathComponent($0).path)
        }
        return kind(having: Set(markers))
    }

    public static func testCommand(in workspace: URL) -> String? {
        switch kind(in: workspace) {
        case .swift: "swift test"
        case .python: "uv run pytest"
        case nil: nil
        }
    }

    public static func lintCommand(in workspace: URL) -> String? {
        let ruffTarget = ["pyproject.toml", ".ruff.toml", "ruff.toml"].contains {
            FileManager.default.fileExists(atPath: workspace.appendingPathComponent($0).path)
        }
        return ruffTarget ? "uv run ruff check --output-format=json" : nil
    }

    /// Restricts a selector to a single shell-word alphabet before it is
    /// appended to a host-derived command.
    public static func isValidSelector(_ selector: String) -> Bool {
        // `::` is pytest's test-node separator; it stays a single shell word.
        let allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-:"
        return !selector.isEmpty && selector.allSatisfy { $0.isASCII && allowed.contains($0) }
    }
}
