import Foundation

extension String {
    /// The string with surrounding whitespace and newlines removed, or nil
    /// when nothing is left.
    public var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension URL {
    /// The last path component, for a folder's short label; "/" for the root.
    public var leafName: String {
        let name = lastPathComponent
        return name.isEmpty ? path : name
    }
}
