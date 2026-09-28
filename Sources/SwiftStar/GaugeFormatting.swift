import Foundation

/// Health level of a gauge. Views map it to a color; this file never does.
enum Severity: Equatable, Hashable {
    case healthy
    case warning
    case critical
}

// Absolute-token curve, not a fraction of the window: warning at about half of
// the 51,200-token default context, critical at about 73%, so critical is
// reachable at that size.
private let contextWarningTokens = 25_000
private let contextCriticalTokens = 37_500

func contextSeverity(ctxUsed: Int) -> Severity {
    if ctxUsed >= contextCriticalTokens { return .critical }
    if ctxUsed >= contextWarningTokens { return .warning }
    return .healthy
}

/// Right-aligns `text` in a field of `width` characters so a changing value
/// does not shift the text around it.
func fixedWidth(_ text: String, width: Int) -> String {
    if text.count >= width { return text }
    return String(repeating: " ", count: width - text.count) + text
}
