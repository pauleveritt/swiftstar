import Foundation

/// One entry in the toolbar model menu (P19.1 D4): each registry variant, then
/// a custom-file escape.
public struct ModelChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }

    public static let defaultID = "default"
    public static let customID = "custom"

    /// The menu's enumeration: the registry variants, then the custom-file
    /// escape. There is no separate "default" entry — Laguna S (P22) is now a
    /// registry variant in its own right (`VariantRegistry.lagunaS`), which is
    /// also what `AgentDefaultSettings.effectiveSelectedVariantID` resolves to
    /// when nothing is configured. A hardcoded "Laguna S (default)" entry
    /// alongside it would be a second menu row selecting the identical model —
    /// `defaultID` is kept only so a stored id from before this change (or an
    /// explicit `modelPath`/`SWIFTSTAR_MODEL` override) still resolves rather
    /// than refusing to match any entry.
    public static func list(variants: [Variant]) -> [ModelChoice] {
        var out = variants.map { ModelChoice(id: $0.id, label: $0.displayName) }
        out.append(ModelChoice(id: customID, label: "Custom file…"))
        return out
    }
}
