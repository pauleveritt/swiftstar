import Foundation

/// A file the transcript names, resolved to the copy Quick Look opens
/// (SU.16, D1): the engine's, in its candidate worktree, while the session
/// runs and the worktree holds the file; else the checkout's.
public struct FileLink: Equatable, Sendable {
    /// Relative to the repository root.
    public let path: String
    public let url: URL
    public let isEngineCopy: Bool

    public init(path: String, url: URL, isEngineCopy: Bool) {
        self.path = path
        self.url = url
        self.isEngineCopy = isEngineCopy
    }

    /// "Quick Look Severity.swift (the engine's copy)".
    public var help: String {
        "Quick Look \(url.lastPathComponent)" + (isEngineCopy ? " (the engine's copy)" : "")
    }

    public static let scheme = "swiftstar-file"

    /// A Markdown link destination for `path`: no space or parenthesis left
    /// in it, so it can't end the destination early (D7).
    public static func destination(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return "\(scheme):" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
    }

    /// The path a `destination(_:)` holds; nil for any other link.
    public static func path(fromDestination destination: String) -> String? {
        guard destination.hasPrefix("\(scheme):") else { return nil }
        return String(destination.dropFirst(scheme.count + 1)).removingPercentEncoding
    }
}

/// Resolves the text a transcript shows to a `FileLink` (D1, D2, D8). Pure:
/// the disk is `exists`, so it's tested without one. Text outside the
/// repository, or naming no file, doesn't resolve.
public struct FileLinkResolver: Sendable {
    public let source: URL?
    public let worktree: URL?
    /// The checkout's tracked files, relative (`EngineController.workspaceFiles`).
    public let known: Set<String>
    private let exists: @Sendable (URL) -> Bool
    /// For bare names (D2): each file name and the known paths that end in it.
    private let byName: [String: [String]]

    public init(source: URL?, worktree: URL?, known: Set<String>, exists: @escaping @Sendable (URL) -> Bool) {
        self.source = source
        self.worktree = worktree
        self.known = known
        self.exists = exists
        byName = Dictionary(grouping: known) { ($0 as NSString).lastPathComponent }
    }

    public func resolve(_ text: String) -> FileLink? {
        guard let path = Self.relative(text, roots: [source, worktree].compactMap { $0 }) else { return nil }
        // A bare name stands for the one known path it ends (D2).
        let candidates: [String] = if path.contains("/") || known.contains(path) {
            [path]
        } else {
            byName[path].flatMap { $0.count == 1 ? $0 : nil } ?? [path]
        }
        guard candidates.count == 1, let path = candidates.first else { return nil }
        if let worktree {
            let url = worktree.appending(path: path)
            if exists(url) { return FileLink(path: path, url: url, isEngineCopy: true) }
        }
        if let source {
            let url = source.appending(path: path)
            if exists(url) { return FileLink(path: path, url: url, isEngineCopy: false) }
        }
        return nil
    }

    /// `text` as a relative path: trimmed, without `./` or a `:line[:col]`
    /// suffix, and an absolute path under one of `roots` made relative. Nil
    /// for anything that can't be a file path here.
    static func relative(_ text: String, roots: [URL]) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = t.range(of: #":\d+(:\d+)?$"#, options: .regularExpression) {
            t.removeSubrange(suffix)
        }
        if t.hasPrefix("/") {
            guard let root = roots.first(where: { t.hasPrefix($0.path + "/") }) else { return nil }
            t = String(t.dropFirst(root.path.count + 1))
        }
        while t.hasPrefix("./") { t.removeFirst(2) }
        guard !t.isEmpty, !t.hasSuffix("/"), !t.contains("://"), !t.contains(" ") || t.contains("/"),
              !t.split(separator: "/").contains("..")
        else { return nil }
        return t
    }
}
