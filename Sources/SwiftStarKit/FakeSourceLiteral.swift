import Foundation

/// Escapes a string for embedding as a Swift string literal in generated
/// source (backslash, quote, newline, carriage return, tab, and any other
/// ASCII control character). Shared by the fake engine/app source generators
/// (extracted from `FakeServerSource` when the Chat server surface retired,
/// 2026-08-26).
public enum FakeSourceLiteral {
    public static func swiftStringLiteral(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.isASCII, CharacterSet.controlCharacters.contains(scalar) {
                    out += "\\u{\(String(scalar.value, radix: 16))}"
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
