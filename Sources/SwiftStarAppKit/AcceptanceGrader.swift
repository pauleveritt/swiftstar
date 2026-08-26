import Foundation
import SwiftStarKit

/// Runs the harness-owned acceptance suite in a worktree (the pytest run that
/// used to be inline in `main.swift`). Writes `test_acceptance.py` into the
/// worktree and runs `uv run --project <pyProject> pytest -q test_acceptance.py`
/// with cwd = the worktree, returning a `GradeResult`. Shared by `main.swift`
/// (first grade) and `RepairLoop` (re-grade after each candidate).
public enum AcceptanceGrader {

    /// The probe that replaces a collection abort (V2 fix, 2026-08-26).
    ///
    /// The acceptance suite does its imports and its seed snapshot at module
    /// level, so pytest aborts collection at the *first* unmet requirement and
    /// reports exactly one error no matter how much is missing. Measured over
    /// the 2026-08-26 matrix, that made the failure surface strictly serial:
    /// 21 of 21 Mellum cells that reached acceptance repair were shown one
    /// error per round against a two-round budget, and **not one repair round
    /// in 80 cells was ever shown a failing assertion.**
    ///
    /// This walks the suite's own module-level AST and checks every
    /// requirement *independently*, so a single grade names all of them at
    /// once. It is deliberately derived from the suite rather than hardcoded —
    /// the suite is harness-owned and may change, and a hardcoded list would
    /// silently rot.
    private static let probeSource = """
    import ast, importlib

    tree = ast.parse(open("test_acceptance.py").read())

    reqs = []
    imported = set()
    for node in tree.body:
        if isinstance(node, ast.Import):
            for a in node.names:
                imported.add(a.name)
                reqs.append(("import " + a.name, a.name, None))
        elif isinstance(node, ast.ImportFrom) and node.module:
            for a in node.names:
                reqs.append(("from " + node.module + " import " + a.name, node.module, a.name))

    class AttrFinder(ast.NodeVisitor):
        def __init__(self):
            self.found = []
        def visit_Attribute(self, node):
            if isinstance(node.value, ast.Name):
                self.found.append((node.value.id, node.attr))
            self.generic_visit(node)

    finder = AttrFinder()
    for node in tree.body:
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            finder.visit(node)
    for mod, attr in dict.fromkeys(finder.found):
        if mod in imported:
            reqs.append((mod + "." + attr, mod, attr))

    lines = []
    unmet = 0
    for label, module, attr in reqs:
        try:
            obj = importlib.import_module(module)
            if attr is not None:
                getattr(obj, attr)
            lines.append("  [MET]   " + label)
        except Exception as exc:
            unmet += 1
            lines.append("  [UNMET] " + label + " -- " + type(exc).__name__ + ": " + str(exc))

    print("Acceptance preconditions. Each is checked on its own, so this names EVERY")
    print("unmet requirement at once instead of stopping at the first one.")
    print("None of the suite's tests can run until all of them are met.")
    print("")
    for line in lines:
        print(line)
    print("")
    print(str(unmet) + " of " + str(len(reqs)) + " preconditions unmet.")
    """

    /// pytest aborted before running anything: it names one error and stops.
    static func collectionAborted(_ output: String) -> Bool {
        output.contains("error during collection") || output.contains("errors during collection")
    }

    public static func grade(worktree: URL, acceptanceSource: String,
                             pyProject: String) throws -> GradeResult {
        try acceptanceSource.write(
            to: worktree.appendingPathComponent("test_acceptance.py"),
            atomically: true, encoding: .utf8)
        let r = try SubprocessRunner.run(
            "uv run --project \(pyProject) pytest -q test_acceptance.py",
            in: worktree)
        let combined = r.stdout + (r.stderr.isEmpty ? "" : "\n" + r.stderr)
        let exit = r.timedOut ? Int32(124) : r.exit

        // V2: a collection abort is not an enumerable failure surface. Replace
        // it with the manifest -- strictly more information, since it lists
        // every unmet requirement with its own error rather than the first one
        // only. The exit code is untouched: this changes what the model is
        // shown, never whether the run passed.
        if collectionAborted(combined), !r.timedOut,
           let manifest = try? preconditions(worktree: worktree, pyProject: pyProject),
           !manifest.isEmpty {
            return GradeResult(exit: exit, output: manifest)
        }
        return GradeResult(exit: exit, output: combined)
    }

    /// Run the precondition probe in `worktree`. Returns its report, or nil if
    /// the probe itself could not run — in which case the caller keeps pytest's
    /// original output rather than showing the model nothing.
    static func preconditions(worktree: URL, pyProject: String) throws -> String? {
        let probe = worktree.appendingPathComponent(".swiftstar-preconditions.py")
        try probeSource.write(to: probe, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: probe) }
        let r = try SubprocessRunner.run(
            "uv run --project \(pyProject) python .swiftstar-preconditions.py",
            in: worktree)
        guard r.exit == 0, !r.timedOut else { return nil }
        return r.stdout.isEmpty ? nil : r.stdout
    }
}
