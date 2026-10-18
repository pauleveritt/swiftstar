import Foundation
import Testing
@testable import SwiftStarKit

/// SU.16, D1, D2 and D8: which text names a file, and which copy opens.
/// The disk is a set of paths, so nothing here touches the filesystem.
struct FileLinkTests {
    private static let source = URL(fileURLWithPath: "/repo")
    private static let worktree = URL(fileURLWithPath: "/tmp/candidate")
    private static let known: Set<String> = [
        "Package.swift", "Sources/SwiftStarKit/Severity.swift",
        "Sources/A/Model.swift", "Sources/B/Model.swift", "docs/My Notes.md",
    ]

    private static func resolver(worktree: URL? = worktree, onDisk: Set<String>) -> FileLinkResolver {
        FileLinkResolver(source: source, worktree: worktree, known: known) { onDisk.contains($0.path) }
    }

    private static let inCheckout: Set<String> = Set(known.map { "/repo/\($0)" })

    @Test(arguments: [
        "Sources/SwiftStarKit/Severity.swift", "./Sources/SwiftStarKit/Severity.swift",
        "Sources/SwiftStarKit/Severity.swift:12", "Sources/SwiftStarKit/Severity.swift:12:3",
        "/repo/Sources/SwiftStarKit/Severity.swift", "/tmp/candidate/Sources/SwiftStarKit/Severity.swift",
        " Sources/SwiftStarKit/Severity.swift ",
    ]) func normalizes(_ text: String) {
        let link = Self.resolver(onDisk: Self.inCheckout).resolve(text)
        #expect(link == FileLink(
            path: "Sources/SwiftStarKit/Severity.swift",
            url: URL(fileURLWithPath: "/repo/Sources/SwiftStarKit/Severity.swift"), isEngineCopy: false))
    }

    @Test func bareNameLinksWhenUnique() {
        let r = Self.resolver(onDisk: Self.inCheckout)
        #expect(r.resolve("Severity.swift")?.path == "Sources/SwiftStarKit/Severity.swift")
        #expect(r.resolve("Package.swift")?.path == "Package.swift")
        // Two `Model.swift`s: no guess.
        #expect(r.resolve("Model.swift") == nil)
    }

    @Test func worktreeCopyWins() {
        let both = Self.inCheckout.union(["/tmp/candidate/Package.swift"])
        #expect(Self.resolver(onDisk: both).resolve("Package.swift")
                == FileLink(path: "Package.swift", url: URL(fileURLWithPath: "/tmp/candidate/Package.swift"),
                            isEngineCopy: true))
        // The engine removed its worktree: the checkout's copy opens.
        #expect(Self.resolver(worktree: nil, onDisk: both).resolve("Package.swift")?.isEngineCopy == false)
    }

    @Test func newFileInWorktreeLinks() {
        let r = Self.resolver(onDisk: Self.inCheckout.union(["/tmp/candidate/Sources/New.swift"]))
        #expect(r.resolve("Sources/New.swift")?.url == URL(fileURLWithPath: "/tmp/candidate/Sources/New.swift"))
    }

    @Test(arguments: [
        "/etc/hosts", "Sources/Missing.swift", "", "not a path at all", "Sources/", "https://example.com/a.swift",
        "../outside.swift",
    ]) func doesNotLink(_ text: String) {
        // `/repo/../outside.swift` is on this disk as the real one would
        // resolve it: only the `..` guard keeps it from linking.
        let r = Self.resolver(onDisk: Self.inCheckout.union(["/etc/hosts", "/repo/../outside.swift"]))
        #expect(r.resolve(text) == nil)
    }

    @Test func destinationRoundTrips() {
        for path in ["Package.swift", "docs/My Notes.md", "a(b).swift"] {
            let destination = FileLink.destination(path)
            #expect(destination.hasPrefix("swiftstar-file:"))
            #expect(!destination.contains(" ") && !destination.contains("(") && !destination.contains(")"))
            #expect(FileLink.path(fromDestination: destination) == path)
        }
        #expect(FileLink.path(fromDestination: "https://example.com") == nil)
    }
}
