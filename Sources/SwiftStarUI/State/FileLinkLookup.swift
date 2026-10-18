import Foundation
import SwiftStarKit

/// The transcript's file links for one set of inputs: the checkout, the
/// engine's worktree and the tracked files (SU.16). Each text is resolved
/// once (D9): the controller builds a new lookup when an input changes, so
/// the cache never outlives what it was built from.
@MainActor
final class FileLinkLookup {
    let resolver: FileLinkResolver
    private var cache: [String: FileLink?] = [:]

    init(resolver: FileLinkResolver) {
        self.resolver = resolver
    }

    convenience init(source: URL?, worktree: URL?, files: [String]) {
        self.init(resolver: FileLinkResolver(source: source, worktree: worktree, known: Set(files)) {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func resolve(_ text: String) -> FileLink? {
        if let hit = cache[text] { return hit }
        let link = resolver.resolve(text)
        cache[text] = link
        return link
    }
}
