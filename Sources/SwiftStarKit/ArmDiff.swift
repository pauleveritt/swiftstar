import Foundation

/// Refuses to compare two arms of an A/B when they differ by anything the
/// experiment did not declare. Motivated by the same 2026-08-30 incident as
/// `SpawnRecord`: two arms silently differed by `--power 70` vs `100` and
/// were read as an engine speedup instead of a throttle setting. `ArmDiff`
/// is the gate a `swiftstar-eval` run consults before trusting a comparison
/// — it does not run anything itself.
///
/// Pure: no process spawn, no socket, no file I/O — `SpawnRecord` already
/// resolved every fact this type needs, and `SwiftStarKit`'s fast-tier
/// contract holds `ArmDiff` to the same rule.
public enum ArmDiff {
    /// Fields admitted, in addition to the declared `variable` itself,
    /// **only** when `variable == "gitRef"` — an engine A/B necessarily
    /// changes both the engine's SHA and the binary built from it. Never
    /// `argv` wholesale: see the type's own doc comment and
    /// `gitRefDoesNotAdmitArgvOnlySettings`.
    public static let engineBuildKeys: Set<String> = ["engineSHA", "engineBinaryHash"]

    /// Compare `a` and `b`, admitting only:
    ///   - keys `SpawnRecord.mustDifferKeys` already expects to differ on
    ///     every spawn (`captureDirectory`, `startedAt`, `runIndex`);
    ///   - the declared `variable`, when it names an actual differing
    ///     `SpawnRecord` property;
    ///   - when `variable == "gitRef"`, `engineBuildKeys` as well — an
    ///     engine ref change moves both together.
    ///
    /// `declaredRefs`, when given, is the pair of `engineSHA` values the
    /// caller already resolved each arm's declared git ref to (this type
    /// does not resolve refs itself — see the fast-tier contract above). For
    /// a `gitRef` experiment, a resolved `engineSHA` that does not match its
    /// arm's declared ref is refused before any other check, because the
    /// experiment is not comparing what it claims to be comparing.
    ///
    /// Anything else that differs — an undeclared throttle, an app-side SHA
    /// change, a context-size drift — refuses with the offending Swift
    /// property names in `ArmDiffRefusal.undeclared`.
    public static func admit(
        _ a: SpawnRecord, _ b: SpawnRecord,
        variable: String, declaredRefs: (String, String)?
    ) -> Result<Set<String>, ArmDiffRefusal> {
        if variable == "gitRef", let declaredRefs {
            guard a.engineSHA == declaredRefs.0, b.engineSHA == declaredRefs.1 else {
                return .failure(ArmDiffRefusal(
                    undeclared: [],
                    message: """
                    gitRef experiment declared refs resolving to \
                    (\(declaredRefs.0), \(declaredRefs.1)), but the arms' actual \
                    engineSHA is (\(a.engineSHA), \(b.engineSHA)) — a resolved SHA \
                    does not match its arm's declared ref, so this is not the \
                    comparison the experiment claims to be running.
                    """))
            }
        }

        let raw = a.differingKeys(from: b)
        var allowed = raw.intersection(SpawnRecord.mustDifferKeys)
        if raw.contains(variable) { allowed.insert(variable) }
        if variable == "gitRef" { allowed.formUnion(raw.intersection(engineBuildKeys)) }

        let undeclared = raw.subtracting(allowed).sorted()
        guard undeclared.isEmpty else {
            // swiftstarSHA is never admitted by any declared `variable`: a
            // difference there means the two arms ran different HARNESS
            // builds, which is a different experiment than whatever
            // `variable` claims (including "gitRef", which only covers the
            // ENGINE ref — see engineBuildKeys).
            let reason = undeclared.contains("swiftstarSHA")
                ? " swiftstarSHA differs: one harness binary cannot embody two " +
                    "harness refs, so this is not the declared \"\(variable)\" experiment."
                : ""
            let argvDetail = a.argvElementDiff(from: b)
            let argvNote = argvDetail.isEmpty
                ? ""
                : " argv differs at: \(argvDetail.joined(separator: "; "))."
            return .failure(ArmDiffRefusal(
                undeclared: undeclared,
                message: "Refusing: arms declared to differ only by \"\(variable)\" " +
                    "also differ in \(undeclared.joined(separator: ", ")).\(reason)\(argvNote)"))
        }
        return .success(raw)
    }
}

/// Why `ArmDiff.admit` refused a pair of arms. `undeclared` names the Swift
/// property names (`SpawnRecord.differingKeys(from:)`'s vocabulary) that
/// differed without being declared; `message` is the human-readable form,
/// concrete about the actual values where `argv` makes that possible (see
/// `SpawnRecord.argvElementDiff(from:)`).
public struct ArmDiffRefusal: Error, Equatable {
    public let undeclared: [String]
    public let message: String
}
