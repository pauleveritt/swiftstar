import Foundation

/// The composer's `@` file picker (SU.14): which word is being typed, what
/// it matches, and what goes in the field. The filters and the fuzzy match
/// are ds4-engine's own (`relevance.py`, `5451cd7d`), so the picker offers
/// what the TUI's does; the engine attaches the file when the prompt is sent.
public enum FileMentions {
    public static let maxCandidates = 16
    public static let maxFileBytes = 2 * 1024 * 1024
    public static let maxFiles = 20_000
    static let skipDirectories: Set<String> = [
        "node_modules", "__pycache__", "venv", "env", "build", "dist", "target", "out",
        "site-packages", "vendor",
    ]
    static let binarySuffixes: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "pdf", "zip", "gz", "tgz", "bz2", "xz", "7z",
        "tar", "whl", "so", "dylib", "dll", "exe", "o", "a", "class", "jar", "pyc", "gguf", "bin",
        "safetensors", "woff", "woff2", "ttf", "otf", "mp3", "mp4", "mov", "wav", "sqlite", "db",
    ]

    /// What follows the `@` of the text's last word, or nil when that word
    /// isn't a mention being typed (D4: the last word, no caret tracking).
    public static func activeQuery(in text: String) -> String? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        let word = text.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        guard word.first == "@" else { return nil }
        let query = String(word.dropFirst())
        return query.contains("@") ? nil : query
    }

    /// The text with its last word replaced by `@path `; the space closes it.
    public static func insert(_ path: String, into text: String) -> String {
        guard activeQuery(in: text) != nil,
              let start = text.lastIndex(where: \.isWhitespace).map({ text.index(after: $0) }) ?? text.indices.first
        else { return text }
        return String(text[..<start]) + "@" + path + " "
    }

    /// The best `limit` paths for `query`: higher tier first, then higher
    /// score, then path order.
    public static func match(_ query: String, in paths: [String], limit: Int = maxCandidates) -> [String] {
        paths.enumerated()
            .compactMap { i, path in fuzzy(query, path).map { (i, path, $0) } }
            .sorted { a, b in
                if a.2.tier != b.2.tier { return a.2.tier > b.2.tier }
                if a.2.score != b.2.score { return a.2.score > b.2.score }
                return a.0 < b.0
            }
            .prefix(limit)
            .map(\.1)
    }

    /// relevance.py's `fuzzy_match`: tier 3 the file name starts with it, 2
    /// the name holds it, 1 the path holds it, 0 a subsequence; nil when not
    /// even that. Within a tier, runs, word starts and shorter paths score
    /// higher. Case-insensitive; no fragment is tier 0 for every path.
    public static func fuzzy(_ fragment: String, _ path: String) -> (tier: Int, score: Double)? {
        guard !fragment.isEmpty else { return (0, 0) }
        let needle = Array(fragment.lowercased()), hay = Array(path.lowercased())
        let nameStart = (hay.lastIndex(of: "/") ?? -1) + 1
        let shorter = -Double(hay.count) / 100
        let separators: Set<Character> = ["_", "-", ".", " "]
        if let at = find(needle, in: hay, from: nameStart) {
            if at == nameStart { return (3, shorter) }
            return (2, (separators.contains(hay[at - 1]) ? 1 : 0) + shorter)
        }
        if let at = find(needle, in: hay, from: 0) {
            let wordStart = at == 0 || hay[at - 1] == "/" || separators.contains(hay[at - 1])
            return (1, (wordStart ? 1 : 0) + shorter)
        }
        var score = 0.0, at = 0, last = -2
        for char in needle {
            guard let found = hay[at...].firstIndex(of: char) else { return nil }
            score += found == last + 1 ? 1 : 0
            score += found >= nameStart ? 0.5 : 0
            score += found == 0 || hay[found - 1] == "/" || separators.contains(hay[found - 1]) ? 1 : 0
            last = found
            at = found + 1
            if at > hay.count { break }
        }
        return (0, score / Double(needle.count) + shorter)
    }

    private static func find(_ needle: [Character], in hay: [Character], from start: Int) -> Int? {
        guard needle.count <= hay.count - start else { return nil }
        for i in start...(hay.count - needle.count) where Array(hay[i..<(i + needle.count)]) == needle {
            return i
        }
        return nil
    }

    /// relevance.py's `wanted`: a text file a mention can name (no space, no
    /// `@`), no binary suffix, under the size cap; an empty file only if its
    /// name has a dot. A nil size is a file that couldn't be read.
    public static func wanted(_ rel: String, size: Int?) -> Bool {
        let suffix = (rel as NSString).pathExtension.lowercased()
        if binarySuffixes.contains(suffix) { return false }
        if rel.contains("@") || rel.contains(where: \.isWhitespace) { return false }
        guard let size else { return false }
        return (size > 0 && size <= maxFileBytes) || (size == 0 && rel.contains("."))
    }

    /// relevance.py's `skipped_dir`: dot, skip-listed and egg-info directories.
    public static func skipped(directory name: String) -> Bool {
        name.hasPrefix(".") || skipDirectories.contains(name) || name.hasSuffix(".egg-info")
    }

    /// Whether any directory on `rel`'s way down is skipped.
    public static func inSkippedDirectory(_ rel: String) -> Bool {
        rel.split(separator: "/").dropLast().contains { skipped(directory: String($0)) }
    }
}
