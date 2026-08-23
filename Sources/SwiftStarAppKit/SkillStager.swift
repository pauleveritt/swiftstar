import Foundation

/// The P8 skills stager (SwiftStarAppKit, design D3).
///
/// `stage` copies the resolved skills tree into
/// `<workspace>/.swiftstar/skills/` so the agent's confined `read` tool can
/// disclose each skill's `SKILL.md` on demand (progressive disclosure, D2).
/// The copy is recursive and plain (`FileManager.copyItem`); a pre-existing
/// destination is removed first so staging is idempotent across spawns. A
/// missing `skillsDir` throws — the `AgentController` treats that as a
/// non-fatal degrade (the bootstrap index still names skills the agent cannot
/// load; the `read` refuses a missing file, so no fabrication).
public enum SkillStager {
    /// Copy `skillsDir` recursively into `workspace/.swiftstar/skills/`,
    /// returning the destination. Throws when `skillsDir` is missing.
    public static func stage(skillsDir: URL, into workspace: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsDir.path) else {
            throw SkillStagerError.missingSkillsDir(skillsDir)
        }
        let parent = workspace.appendingPathComponent(".swiftstar")
        let dest = parent.appendingPathComponent("skills")
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: skillsDir, to: dest)
        return dest
    }
}

/// Errors thrown by `SkillStager.stage`.
public enum SkillStagerError: Error, Sendable {
    /// The resolved skills dir does not exist (non-fatal degrade at the
    /// controller; the bootstrap still loads without staged skills).
    case missingSkillsDir(URL)
}
