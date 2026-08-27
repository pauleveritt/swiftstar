import Foundation

/// One entry in the toolbar model menu (P19.1 D4): the effective model — the
/// Laguna S default, then each registry variant, then a custom-file escape.
public struct ModelChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }

    public static let defaultID = "default"
    public static let customID = "custom"

    /// The menu's enumeration: the implicit default (Laguna S) first, then the
    /// registry variants, then the custom-file escape. The default is the
    /// fallback, not a registry entry — `VariantRegistry.all` holds only
    /// explicit presets (Mellum today).
    public static func list(variants: [Variant]) -> [ModelChoice] {
        var out = [ModelChoice(id: defaultID, label: "Laguna S (default)")]
        out += variants.map { ModelChoice(id: $0.id, label: $0.displayName) }
        out.append(ModelChoice(id: customID, label: "Custom file…"))
        return out
    }
}
