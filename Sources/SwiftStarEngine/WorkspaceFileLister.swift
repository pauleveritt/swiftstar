import Foundation
import SwiftStarKit

/// The `@` picker's files (SU.14, D5): `git ls-files -z` in the workspace's
/// git root, filtered as ds4-engine's TUI filters them (`FileMentions`).
/// Outside a git checkout, or if git fails, there's nothing to offer.
public enum WorkspaceFileLister {
    public static func list(root: URL, timeout: Duration = .seconds(10)) async -> [String] {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else { return [] }
        let result = await ProcessRunner.run(
            executable: "/usr/bin/git", arguments: ["-C", root.path, "ls-files", "-z"], timeout: timeout)
        guard case .success(let output) = result, output.code == 0 else { return [] }
        var files: [String] = []
        for rel in String(decoding: output.stdout, as: UTF8.self).split(separator: "\0").map(String.init) {
            guard !rel.isEmpty, !FileMentions.inSkippedDirectory(rel) else { continue }
            let size = (try? FileManager.default.attributesOfItem(
                atPath: root.appendingPathComponent(rel).path)[.size] as? Int) ?? nil
            if FileMentions.wanted(rel, size: size) { files.append(rel) }
            if files.count >= FileMentions.maxFiles { break }
        }
        return files
    }
}
