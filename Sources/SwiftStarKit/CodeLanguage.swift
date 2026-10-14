import Foundation

/// The highlight.js language for a tool card's file (SU.15, D3), by its
/// extension or, for a few extensionless names, the name itself. Nil keeps
/// the card plain.
public enum CodeLanguage {
    static let byExtension: [String: String] = [
        "py": "python", "swift": "swift", "md": "markdown", "markdown": "markdown",
        "toml": "ini", "ini": "ini", "cfg": "ini", "json": "json", "yaml": "yaml", "yml": "yaml",
        "sh": "bash", "bash": "bash", "zsh": "bash", "js": "javascript", "mjs": "javascript",
        "ts": "typescript", "tsx": "typescript", "jsx": "javascript", "html": "xml", "xml": "xml",
        "plist": "xml", "css": "css", "rs": "rust", "go": "go", "c": "c", "h": "c", "m": "objectivec",
        "cpp": "cpp", "hpp": "cpp", "cc": "cpp", "java": "java", "kt": "kotlin", "rb": "ruby",
        "sql": "sql", "diff": "diff", "patch": "diff", "jinja": "django", "j2": "django",
    ]
    static let byName: [String: String] = [
        "makefile": "makefile", "dockerfile": "dockerfile", "justfile": "makefile",
    ]

    public static func forPath(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if let language = byName[name] { return language }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : byExtension[ext]
    }
}
